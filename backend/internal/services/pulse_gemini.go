// pulse_gemini.go — PulseDraftWriter backed by the Gemini API via the
// official Go SDK (google.golang.org/genai). One call per day; the reply is
// constrained to a JSON schema (ResponseJsonSchema) and then re-checked by
// draftToInput before anything is saved. See docs/pulse/AUTODRAFT.md.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"google.golang.org/genai"
)

// DefaultPulseDraftModel is used when PULSE_AUTODRAFT_MODEL is unset: the
// newest Gemini model marked stable in Google's model list (2026-11-28).
const DefaultPulseDraftModel = "gemini-3.8-flash"

const (
	pulseDraftMaxTokens = 16000
	pulseDraftTimeout   = 5 * time.Minute
)

// GeminiPulseWriter calls the Gemini API.
type GeminiPulseWriter struct {
	client *genai.Client
	model  string
}

// NewGeminiPulseWriter builds a writer. An empty model uses the default.
func NewGeminiPulseWriter(ctx context.Context, apiKey, model string) (*GeminiPulseWriter, error) {
	if strings.TrimSpace(model) == "" {
		model = DefaultPulseDraftModel
	}
	client, err := genai.NewClient(ctx, &genai.ClientConfig{APIKey: apiKey, Backend: genai.BackendGeminiAPI})
	if err != nil {
		return nil, fmt.Errorf("creating gemini client: %w", err)
	}
	return &GeminiPulseWriter{client: client, model: model}, nil
}

// WriteDrafts asks Gemini for today's picks.
func (w *GeminiPulseWriter) WriteDrafts(ctx context.Context, req PulseDraftRequest) ([]PulseDraft, error) {
	payload, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("encoding draft request: %w", err)
	}
	ctx, cancel := context.WithTimeout(ctx, pulseDraftTimeout)
	defer cancel()
	resp, err := w.client.Models.GenerateContent(ctx, w.model,
		[]*genai.Content{genai.NewContentFromText(string(payload), genai.RoleUser)},
		&genai.GenerateContentConfig{
			SystemInstruction:  genai.NewContentFromText(pulseDraftSystem, genai.RoleUser),
			MaxOutputTokens:    pulseDraftMaxTokens,
			ResponseMIMEType:   "application/json",
			ResponseJsonSchema: pulseDraftSchema,
		})
	if err != nil {
		return nil, fmt.Errorf("gemini request: %w", err)
	}
	return parsePulseDraftReply(resp)
}

// parsePulseDraftReply checks why generation stopped and decodes the JSON.
func parsePulseDraftReply(resp *genai.GenerateContentResponse) ([]PulseDraft, error) {
	if resp.PromptFeedback != nil && resp.PromptFeedback.BlockReason != "" {
		return nil, fmt.Errorf("gemini blocked the request: %s", resp.PromptFeedback.BlockReason)
	}
	if len(resp.Candidates) == 0 {
		return nil, errors.New("gemini returned no candidates")
	}
	switch reason := resp.Candidates[0].FinishReason; reason {
	case genai.FinishReasonStop, "":
	case genai.FinishReasonMaxTokens:
		return nil, errors.New("gemini reply was cut off (MAX_TOKENS)")
	default:
		return nil, fmt.Errorf("gemini stopped early: %s", reason)
	}
	var out struct {
		Items []PulseDraft `json:"items"`
	}
	if err := json.Unmarshal([]byte(resp.Text()), &out); err != nil {
		return nil, fmt.Errorf("decoding gemini reply: %w", err)
	}
	return out.Items, nil
}
