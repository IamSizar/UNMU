// pulse_claude.go — PulseDraftWriter backed by the Claude API
// (docs/pulse/AUTODRAFT.md). One Messages call per day; the reply is
// constrained to a JSON schema (structured outputs) and then re-checked
// by draftToInput before anything is saved.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/anthropics/anthropic-sdk-go/v2"
	"github.com/anthropics/anthropic-sdk-go/v2/option"
)

// DefaultPulseDraftModel is used when PULSE_AUTODRAFT_MODEL is unset.
const DefaultPulseDraftModel = "claude-opus-5-5"

const (
	pulseDraftMaxTokens = 16000
	pulseDraftTimeout   = 5 * time.Minute
)

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
				"additionalProperties": false,
			},
		},
	},
	"required":             []string{"items"},
	"additionalProperties": false,
}

// ClaudePulseWriter calls the Claude API.
type ClaudePulseWriter struct {
	client anthropic.Client
	model  string
}

// NewClaudePulseWriter builds a writer. An empty model uses the default.
func NewClaudePulseWriter(apiKey, model string) *ClaudePulseWriter {
	if strings.TrimSpace(model) == "" {
		model = DefaultPulseDraftModel
	}
	return &ClaudePulseWriter{
		client: anthropic.NewClient(option.WithAPIKey(apiKey), option.WithRequestTimeout(pulseDraftTimeout)),
		model:  model,
	}
}

// WriteDrafts asks Claude for today's picks.
func (w *ClaudePulseWriter) WriteDrafts(ctx context.Context, req PulseDraftRequest) ([]PulseDraft, error) {
	payload, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("encoding draft request: %w", err)
	}
	msg, err := w.client.Beta.Messages.New(ctx, anthropic.BetaMessageNewParams{
		Model:     anthropic.Model(w.model),
		MaxTokens: pulseDraftMaxTokens,
		System:    []anthropic.BetaTextBlockParam{{Text: pulseDraftSystem}},
		Messages:  []anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(string(payload)))},
		OutputConfig: anthropic.BetaOutputConfigParam{
			Effort: anthropic.BetaOutputConfigEffortMedium,
			Format: anthropic.BetaJSONOutputFormatParam{Schema: pulseDraftSchema},
		},
		// Server-side fallback: a policy decline is re-served by another
		// model inside the same call instead of failing the day.
		Fallbacks: anthropic.BetaFallbacksParamOfDefault(),
		Betas:     []anthropic.AnthropicBeta{anthropic.AnthropicBetaServerSideFallback2026_07_01},
	})
	if err != nil {
		return nil, fmt.Errorf("claude request: %w", err)
	}
	return parsePulseDraftReply(msg)
}

// parsePulseDraftReply checks the stop reason and decodes the JSON reply.
func parsePulseDraftReply(msg *anthropic.BetaMessage) ([]PulseDraft, error) {
	switch msg.StopReason {
	case anthropic.BetaStopReasonRefusal:
		return nil, errors.New("claude declined the request")
	case anthropic.BetaStopReasonMaxTokens:
		return nil, errors.New("claude reply was cut off (max_tokens)")
	}
	var text strings.Builder
	for _, block := range msg.Content {
		if tb, ok := block.AsAny().(anthropic.BetaTextBlock); ok {
			text.WriteString(tb.Text)
		}
	}
	var out struct {
		Items []PulseDraft `json:"items"`
	}
	if err := json.Unmarshal([]byte(text.String()), &out); err != nil {
		return nil, fmt.Errorf("decoding claude reply: %w", err)
	}
	return out.Items, nil
}
