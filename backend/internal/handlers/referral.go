package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// referralRewardPercent is the discount each side of a successful referral
// gets, applied as a one-time promo code (reusing the existing, already-
// tested promo redemption path instead of writing new billing logic).
//
// SHARIAH-REVIEW N/A (not a fiqh question) but flagged for PRODUCT sign-off:
// this number is a placeholder. Confirm the intended reward before shipping
// to production — it directly affects revenue per acquired user.
const referralRewardPercent = 20.0

// ReferralHandler exposes the give-one-get-one referral program: every user
// has a personal code (GetMyCode), can see how many friends they've
// referred (GetStats), and a new user redeems a code once (Redeem) to mint
// a reward promo for both sides.
type ReferralHandler struct {
	referrals *repositories.ReferralRepository
	promos    *repositories.PromoCodeRepository
}

func NewReferralHandler(referrals *repositories.ReferralRepository, promos *repositories.PromoCodeRepository) *ReferralHandler {
	return &ReferralHandler{referrals: referrals, promos: promos}
}

// GetMyCode — GET /api/referrals/my-code (auth). Returns (creating on
// first call) the caller's personal referral code.
func (h *ReferralHandler) GetMyCode(c *gin.Context) {
	userID := c.GetInt64("user_id")

	code, err := h.referrals.GetOrCreateCode(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get referral code"})
		return
	}

	pct := strconv.Itoa(int(referralRewardPercent))
	c.JSON(http.StatusOK, gin.H{
		"code":          code,
		"rewardPercent": referralRewardPercent,
		"shareMessage":  "Join me on UNMU and screen your investments for Shariah compliance. Use my code " + code + " and we both get " + pct + "% off Pro.",
	})
}

// GetStats — GET /api/referrals/stats (auth). How many successful
// referrals this user has made.
func (h *ReferralHandler) GetStats(c *gin.Context) {
	userID := c.GetInt64("user_id")

	count, err := h.referrals.CountByReferrer(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load referral stats"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"referralCount": count})
}

type redeemReferralRequest struct {
	Code string `json:"code" binding:"required"`
}

// Redeem — POST /api/referrals/redeem (auth). Called once, right after
// signup, when a new user enters someone else's referral code. Mints a
// one-time reward promo code for BOTH the referrer and the new user.
//
// Rejected when: the code doesn't exist, the caller is trying to redeem
// their own code (self-referral), or the caller has already redeemed a
// referral before (enforced here AND by the UNIQUE(referred_user_id)
// constraint in migration 0055 — belt and suspenders against a race).
func (h *ReferralHandler) Redeem(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req redeemReferralRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	code := strings.ToUpper(strings.TrimSpace(req.Code))
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Referral code is required"})
		return
	}

	referrerID, err := h.referrals.LookupOwner(code)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to look up referral code"})
		return
	}
	if referrerID == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Invalid referral code"})
		return
	}
	if referrerID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "You can't redeem your own referral code"})
		return
	}

	// Atomically claim the "one referral per new user" slot BEFORE minting
	// any promo code — closes the race between two concurrent redemptions
	// for the same new user, and guarantees a losing request never creates
	// an orphaned reward. See ReferralRepository.ClaimSlot.
	referralID, claimed, err := h.referrals.ClaimSlot(referrerID, userID, code)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to record referral"})
		return
	}
	if !claimed {
		c.JSON(http.StatusConflict, gin.H{"error": "You've already redeemed a referral code"})
		return
	}

	one := int64(1)
	validUntil := time.Now().AddDate(0, 3, 0) // reward expires in 3 months if unused
	// Codes are keyed by the referral row's own id, which is unique per
	// redemption — unlike keying by the shared referral `code`, this can't
	// collide on a referrer's 2nd, 3rd, ... successful referral.
	refID := strconv.FormatInt(referralID, 10)

	referrerPromo, err := h.promos.Create(repositories.PromoMutation{
		Code:          "REF-" + refID + "-R",
		DiscountType:  "PERCENTAGE",
		DiscountValue: referralRewardPercent,
		Scope:         "all",
		MaxUses:       &one,
		ValidUntil:    &validUntil,
	})
	if err != nil {
		// The referral slot is already claimed at this point — a failure
		// here leaves a referral row with NULL promo ids (see
		// AttachPromoIDs' doc comment) rather than a double reward.
		status := http.StatusInternalServerError
		if errors.Is(err, repositories.ErrPromoCodeExists) {
			status = http.StatusConflict // refID is unique per row, so this means a retry replayed the same request
		}
		c.JSON(status, gin.H{"error": "Failed to create referrer reward"})
		return
	}

	referredPromo, err := h.promos.Create(repositories.PromoMutation{
		Code:          "REF-" + refID + "-N",
		DiscountType:  "PERCENTAGE",
		DiscountValue: referralRewardPercent,
		Scope:         "all",
		MaxUses:       &one,
		ValidUntil:    &validUntil,
	})
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, repositories.ErrPromoCodeExists) {
			status = http.StatusConflict
		}
		c.JSON(status, gin.H{"error": "Failed to create referral reward"})
		return
	}

	if err := h.referrals.AttachPromoIDs(referralID, referrerPromo.ID, referredPromo.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to finalize referral"})
		return
	}

	pct := strconv.Itoa(int(referralRewardPercent))
	c.JSON(http.StatusOK, gin.H{
		"success":    true,
		"yourReward": referredPromo.Code,
		"message":    "Referral applied! Use code " + referredPromo.Code + " to get " + pct + "% off Pro.",
	})
}
