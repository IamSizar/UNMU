// pulse_autodraft_rules.go — the checks every machine-written Pulse pick
// must pass before it is saved as a draft (docs/pulse/AUTODRAFT.md).
package services

import (
	"errors"
	"fmt"
	"net/url"
	"strings"

	"halalstocks/internal/models"
)

// draftToInput checks one pick and turns it into a draft input. The source
// always comes from the fetched article (or our screening data), never
// from the model's text, and verified_at stays empty so a person must
// verify before the item can leave draft.
func draftToInput(
	dr PulseDraft, req PulseDraftRequest, stockIDs map[string]int, used map[string]bool,
) (models.PulseItemInput, error) {
	var in models.PulseItemInput
	if !containsString(req.OpenSlots, dr.Slot) || used[dr.Slot] {
		return in, fmt.Errorf("slot %q is not open", dr.Slot)
	}
	if dr.Classification != "confirmed" && dr.Classification != "analysis" {
		return in, fmt.Errorf("bad classification %q", dr.Classification)
	}
	if err := requireText(dr); err != nil {
		return in, err
	}
	name, link, err := draftSource(dr, req)
	if err != nil {
		return in, err
	}
	in = models.PulseItemInput{
		PulseDate: req.Date, Slot: dr.Slot, Classification: dr.Classification,
		IsSensitive: dr.Slot == "sharia",
		TitleAr:     dr.TitleAr, TitleEn: dr.TitleEn, SummaryAr: dr.SummaryAr, SummaryEn: dr.SummaryEn,
		DetailsAr: dr.DetailsAr, DetailsEn: dr.DetailsEn, EvidenceAr: dr.EvidenceAr, EvidenceEn: dr.EvidenceEn,
		SourceName: name, SourceURL: link,
	}
	if id, ok := stockIDs[strings.ToUpper(strings.TrimSpace(dr.StockTicker))]; ok {
		in.StockID = &id
	}
	return in, nil
}

// draftSource resolves the cited source for a pick.
func draftSource(dr PulseDraft, req PulseDraftRequest) (string, string, error) {
	if dr.ArticleIndex == noArticle {
		if dr.Slot == "sharia" && len(req.ShariahChanges) > 0 {
			return ShariahDataSource, "", nil
		}
		return "", "", errors.New("no article cited")
	}
	if dr.ArticleIndex < 0 || dr.ArticleIndex >= len(req.Articles) {
		return "", "", fmt.Errorf("article %d does not exist", dr.ArticleIndex)
	}
	a := req.Articles[dr.ArticleIndex]
	return a.Source, a.Link, nil
}

// requireText rejects a pick with any empty text field: both languages are
// needed before an item can leave draft anyway.
func requireText(dr PulseDraft) error {
	fields := map[string]string{
		"title_ar": dr.TitleAr, "title_en": dr.TitleEn, "summary_ar": dr.SummaryAr,
		"summary_en": dr.SummaryEn, "details_ar": dr.DetailsAr, "details_en": dr.DetailsEn,
		"evidence_ar": dr.EvidenceAr, "evidence_en": dr.EvidenceEn,
	}
	for name, v := range fields {
		if strings.TrimSpace(v) == "" {
			return fmt.Errorf("%s is empty", name)
		}
	}
	return nil
}

func containsString(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

func sourceHost(link string) string {
	u, err := url.Parse(link)
	if err != nil || u.Host == "" {
		return link
	}
	return strings.TrimPrefix(u.Host, "www.")
}

func clipRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}
