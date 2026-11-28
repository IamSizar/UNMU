// pulse_draft_prompt.go — the editor brief and output schema shared by the
// Pulse draft writer (docs/pulse/AUTODRAFT.md). Provider-neutral: the
// writer sends them to the model, and draftToInput re-checks every pick.
package services

// pulseDraftSystem is the editor brief. Kept stable (no dates) so it can
// be cached; the day's data goes in the user message.
const pulseDraftSystem = `You draft items for UNMU Pulse (نبض أنمو), a short daily market briefing for Muslim investors in Iraq and the Gulf. Human editors verify, review and approve every draft, so accuracy matters more than filling slots.

You get a JSON object: the date, the open slots, numbered news articles, recent Sharia screening changes from our own data, and the tickers we cover. Pick at most one story for each open slot:
- global: the most important global market or economy story of the day.
- gulf: a story about Gulf or MENA markets, companies or economies (Saudi, UAE, Qatar, Kuwait, Bahrain, Oman, Iraq, Jordan, Egypt). Leave it out if no article is about this region.
- sharia: a Sharia screening change from shariahChanges (set article_index to -1 and explain what changed and why, using only the given status, reason and ratios), or an article about Islamic finance. Leave it out if neither exists.
- opportunity: a covered stock with notable news. Describe what happened and why it may matter. Never tell the reader to buy, sell or hold.

Rules:
- Use only facts that are in the given articles or screening data. Never add numbers, quotes, dates or claims that are not there.
- classification "confirmed" means the item reports facts stated in the source; "analysis" means it interprets them. Use "analysis" whenever you add any interpretation.
- article_index is the index of the article you used (or -1 only for a sharia item built from shariahChanges).
- stock_ticker is the related covered ticker, or "" if none.
- Arabic is Modern Standard Arabic, written natively, not a word-for-word translation. Arabic and English must say the same thing.
- title: at most 90 characters. summary: one or two sentences. details: two to four short paragraphs. evidence: the specific facts and figures from the source that support the item, with the source's date.
- Leave a slot out rather than force a weak or off-topic story.`

// pulseDraftSchema is the structured-output schema for the reply.
var pulseDraftSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"items": map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"slot":           map[string]any{"type": "string", "enum": pulseSlots},
					"article_index":  map[string]any{"type": "integer"},
					"classification": map[string]any{"type": "string", "enum": []string{"confirmed", "analysis"}},
					"title_ar":       map[string]any{"type": "string"},
					"title_en":       map[string]any{"type": "string"},
					"summary_ar":     map[string]any{"type": "string"},
					"summary_en":     map[string]any{"type": "string"},
					"details_ar":     map[string]any{"type": "string"},
					"details_en":     map[string]any{"type": "string"},
					"evidence_ar":    map[string]any{"type": "string"},
					"evidence_en":    map[string]any{"type": "string"},
					"stock_ticker":   map[string]any{"type": "string"},
				},
				"required": []string{"slot", "article_index", "classification", "title_ar", "title_en",
					"summary_ar", "summary_en", "details_ar", "details_en", "evidence_ar", "evidence_en", "stock_ticker"},
			},
		},
	},
	"required": []string{"items"},
}
