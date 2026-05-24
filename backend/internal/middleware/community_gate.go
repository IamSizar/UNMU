package middleware

import (
	"net/http"
	"strings"

	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// CommunityGate is the server-side enforcement of the admin community
// kill-switch. Applied once to the /api group; it path-matches the matched
// route pattern (c.FullPath) so a single middleware covers every community
// route — public listings, joins, posts, chat, polls, subscriptions.
//
//   - community_enabled OFF  → block ALL community routes (master switch).
//   - community_chat_enabled OFF  → block chat + polls only.
//   - community_posts_enabled OFF → block community posts only.
//
// Admin routes (/api/admin/...) are always exempt so the admin can manage
// and re-enable even while the feature is dark. Non-community routes pass
// through untouched (a cheap string check).
func CommunityGate(settings *repositories.AppSettingsRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		p := c.FullPath()

		// Admin endpoints always work (the toggle itself + moderation).
		if strings.Contains(p, "/admin/") {
			c.Next()
			return
		}
		// Not a community route → nothing to gate. Matches communities,
		// community-invitations, community-subscriptions, community-proposals,
		// /me/communities, etc.
		if !strings.Contains(p, "communit") {
			c.Next()
			return
		}

		if !settings.CommunityEnabled() {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "Communities are currently unavailable.",
				"code":  "COMMUNITY_DISABLED",
			})
			return
		}
		// Chat + polls live inside the community chat.
		if (strings.Contains(p, "/messages") || strings.Contains(p, "/polls")) &&
			!settings.CommunityChatEnabled() {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "Community chat is currently unavailable.",
				"code":  "COMMUNITY_CHAT_DISABLED",
			})
			return
		}
		// Community posts (NOT expert posts — those routes don't contain
		// "communit", so they never reach here).
		if strings.Contains(p, "/posts") && !settings.CommunityPostsEnabled() {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "Community posts are currently unavailable.",
				"code":  "COMMUNITY_POSTS_DISABLED",
			})
			return
		}

		c.Next()
	}
}
