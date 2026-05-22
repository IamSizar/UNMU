package services

import (
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/resend/resend-go/v3"
)

// EmailSender wraps net/smtp with a small ergonomic API. It speaks plain
// SMTP with STARTTLS (port 587) or implicit TLS (port 465) — both are
// supported by every transactional provider we'd realistically pick
// (SendGrid, Postmark, Mailgun, Resend, Amazon SES, Gmail SMTP).
//
// Soft-fail: when SMTP_HOST is unset, NewEmailSender returns nil. Callers
// must nil-check before sending — when nil, the caller is expected to fall
// back to logging the would-have-been email body (we already do that for
// verification codes in dev mode).
//
// Env vars:
//
//	SMTP_HOST       (required)  e.g. "smtp.sendgrid.net"
//	SMTP_PORT       (optional, default 587)
//	SMTP_USER       (optional)  SMTP username. For SendGrid this is the
//	                            literal string "apikey".
//	SMTP_PASSWORD   (optional)  SMTP password / API key.
//	SMTP_FROM       (required)  the From: address (must be a verified
//	                            sender at the provider).
//	SMTP_FROM_NAME  (optional, default "UNMU")
//	APP_PUBLIC_URL  (optional, default "https://unmu.app") — used by
//	                            password-reset emails to build the link.
type EmailSender struct {
	host     string
	port     int
	username string
	password string
	from     string
	fromName string

	// Resend transport. When resendClient is non-nil, Send() delivers via
	// the Resend HTTP API instead of raw SMTP. Configured from
	// RESEND_API_KEY (+ optional RESEND_FROM). Resend is preferred over
	// SMTP when both happen to be set.
	resendClient *resend.Client
	resendFrom   string
}

// NewEmailSender returns a configured sender, or nil when NEITHER Resend
// nor SMTP is configured. nil is a soft-fail signal — callers log a
// warning and fall back to stdout-only output (the dev-mode behavior).
//
// Transport precedence: if RESEND_API_KEY is set we use Resend; otherwise
// we fall back to SMTP (when SMTP_HOST is set).
func NewEmailSender() *EmailSender {
	resendKey := strings.TrimSpace(os.Getenv("RESEND_API_KEY"))
	host := strings.TrimSpace(os.Getenv("SMTP_HOST"))
	if resendKey == "" && host == "" {
		return nil
	}

	fromName := strings.TrimSpace(os.Getenv("SMTP_FROM_NAME"))
	if fromName == "" {
		fromName = "UNMU"
	}
	e := &EmailSender{fromName: fromName}

	// ── Resend transport (preferred) ──────────────────────────────────
	if resendKey != "" {
		resendFrom := strings.TrimSpace(os.Getenv("RESEND_FROM"))
		if resendFrom == "" {
			// Resend's shared test sender. NOTE: with this address Resend
			// only delivers to YOUR Resend account email. Verify a domain
			// and set RESEND_FROM=noreply@yourdomain to reach any user.
			resendFrom = "onboarding@resend.dev"
		}
		e.resendClient = resend.NewClient(resendKey)
		e.resendFrom = resendFrom
		log.Printf("[email] Resend configured: from=%q (verify your domain + set "+
			"RESEND_FROM to send to addresses other than your Resend account)", resendFrom)
		return e
	}

	// ── SMTP transport (fallback) ─────────────────────────────────────
	port, _ := strconv.Atoi(strings.TrimSpace(os.Getenv("SMTP_PORT")))
	if port == 0 {
		port = 587
	}
	from := strings.TrimSpace(os.Getenv("SMTP_FROM"))
	if from == "" {
		from = strings.TrimSpace(os.Getenv("SMTP_USER"))
	}
	if from == "" {
		log.Printf("[email] SMTP_HOST set but SMTP_FROM is empty — emails will fail")
	}
	e.host = host
	e.port = port
	e.username = strings.TrimSpace(os.Getenv("SMTP_USER"))
	e.password = strings.TrimSpace(os.Getenv("SMTP_PASSWORD"))
	e.from = from
	log.Printf("[email] SMTP configured: host=%s port=%d from=%q", host, port, from)
	return e
}

// Send delivers a single multipart/alternative email (text + html parts).
// Returns an error when SMTP rejects the message; non-nil is logged but
// not surfaced to the user (we don't want a flaky SMTP to break signup).
func (e *EmailSender) Send(to, subject, htmlBody, textBody string) error {
	if e == nil {
		return fmt.Errorf("email: sender not configured (SMTP_HOST unset)")
	}
	to = strings.TrimSpace(to)
	if to == "" {
		return fmt.Errorf("email: empty recipient")
	}

	// Resend transport takes priority when configured.
	if e.resendClient != nil {
		return e.sendResend(to, subject, htmlBody, textBody)
	}

	boundary, err := randHex(12)
	if err != nil {
		return fmt.Errorf("email: rand: %w", err)
	}

	var msg strings.Builder
	fmt.Fprintf(&msg, "From: %s <%s>\r\n", encodeHeader(e.fromName), e.from)
	fmt.Fprintf(&msg, "To: %s\r\n", to)
	fmt.Fprintf(&msg, "Subject: %s\r\n", encodeHeader(subject))
	fmt.Fprintf(&msg, "Date: %s\r\n", time.Now().UTC().Format(time.RFC1123Z))
	fmt.Fprintf(&msg, "MIME-Version: 1.0\r\n")
	fmt.Fprintf(&msg, "Content-Type: multipart/alternative; boundary=\"%s\"\r\n\r\n", boundary)

	fmt.Fprintf(&msg, "--%s\r\n", boundary)
	fmt.Fprintf(&msg, "Content-Type: text/plain; charset=\"UTF-8\"\r\n")
	fmt.Fprintf(&msg, "Content-Transfer-Encoding: 8bit\r\n\r\n")
	msg.WriteString(textBody)
	msg.WriteString("\r\n")

	fmt.Fprintf(&msg, "--%s\r\n", boundary)
	fmt.Fprintf(&msg, "Content-Type: text/html; charset=\"UTF-8\"\r\n")
	fmt.Fprintf(&msg, "Content-Transfer-Encoding: 8bit\r\n\r\n")
	msg.WriteString(htmlBody)
	msg.WriteString("\r\n")

	fmt.Fprintf(&msg, "--%s--\r\n", boundary)

	addr := fmt.Sprintf("%s:%d", e.host, e.port)

	// Port 465 is implicit TLS (SMTPS); everything else uses STARTTLS over
	// the plaintext socket. We dial both paths manually rather than using
	// smtp.SendMail so we can negotiate STARTTLS reliably.
	if e.port == 465 {
		return e.sendImplicitTLS(addr, to, []byte(msg.String()))
	}
	return e.sendStartTLS(addr, to, []byte(msg.String()))
}

// sendResend delivers via the Resend HTTP API. The From header carries
// the friendly name when set: "UNMU <onboarding@resend.dev>".
func (e *EmailSender) sendResend(to, subject, htmlBody, textBody string) error {
	from := e.resendFrom
	if e.fromName != "" {
		from = fmt.Sprintf("%s <%s>", e.fromName, e.resendFrom)
	}
	sent, err := e.resendClient.Emails.Send(&resend.SendEmailRequest{
		From:    from,
		To:      []string{to},
		Subject: subject,
		Html:    htmlBody,
		Text:    textBody,
	})
	if err != nil {
		return fmt.Errorf("resend send: %w", err)
	}
	log.Printf("[email] sent via Resend id=%s to=%s", sent.Id, to)
	return nil
}

func (e *EmailSender) sendStartTLS(addr, to string, msg []byte) error {
	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("smtp dial: %w", err)
	}
	c, err := smtp.NewClient(conn, e.host)
	if err != nil {
		conn.Close()
		return fmt.Errorf("smtp client: %w", err)
	}
	defer c.Close()

	if ok, _ := c.Extension("STARTTLS"); ok {
		if err := c.StartTLS(&tls.Config{ServerName: e.host}); err != nil {
			return fmt.Errorf("smtp starttls: %w", err)
		}
	}
	return e.writeMessage(c, to, msg)
}

func (e *EmailSender) sendImplicitTLS(addr, to string, msg []byte) error {
	conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: e.host})
	if err != nil {
		return fmt.Errorf("smtps dial: %w", err)
	}
	c, err := smtp.NewClient(conn, e.host)
	if err != nil {
		conn.Close()
		return fmt.Errorf("smtps client: %w", err)
	}
	defer c.Close()
	return e.writeMessage(c, to, msg)
}

func (e *EmailSender) writeMessage(c *smtp.Client, to string, msg []byte) error {
	if e.username != "" {
		auth := smtp.PlainAuth("", e.username, e.password, e.host)
		if err := c.Auth(auth); err != nil {
			return fmt.Errorf("smtp auth: %w", err)
		}
	}
	if err := c.Mail(e.from); err != nil {
		return fmt.Errorf("smtp mail-from: %w", err)
	}
	if err := c.Rcpt(to); err != nil {
		return fmt.Errorf("smtp rcpt-to: %w", err)
	}
	w, err := c.Data()
	if err != nil {
		return fmt.Errorf("smtp data: %w", err)
	}
	if _, err := w.Write(msg); err != nil {
		return fmt.Errorf("smtp write: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("smtp close: %w", err)
	}
	return c.Quit()
}

// SendVerificationCode — 6-digit OTP for new-account email verification.
// Falls back to a generic "User" greeting if name is empty.
func (e *EmailSender) SendVerificationCode(to, name, code string) error {
	greeting := strings.TrimSpace(name)
	if greeting == "" {
		greeting = "there"
	}
	subject := "Your UNMU verification code"
	text := fmt.Sprintf(
		"Hi %s,\n\nYour UNMU verification code is: %s\n\n"+
			"This code expires in 10 minutes. If you didn't request this, you can safely ignore this email.\n\n— UNMU",
		greeting, code,
	)
	html := fmt.Sprintf(verificationHTML, greeting, code)
	return e.Send(to, subject, html, text)
}

// SendPasswordReset — link with one-time token; expires in 1 hour.
func (e *EmailSender) SendPasswordReset(to, name, link string) error {
	greeting := strings.TrimSpace(name)
	if greeting == "" {
		greeting = "there"
	}
	subject := "Reset your UNMU password"
	text := fmt.Sprintf(
		"Hi %s,\n\nWe got a request to reset your UNMU password. "+
			"Copy this link and paste it into the UNMU app's reset screen "+
			"(it expires in 1 hour):\n\n%s\n\n"+
			"If you didn't request this, ignore this email — your password is unchanged.\n\n— UNMU",
		greeting, link,
	)
	html := fmt.Sprintf(passwordResetHTML, greeting, link, link)
	return e.Send(to, subject, html, text)
}

// PublicAppURL returns the canonical https URL for the marketing site /
// deep-link host. Defaults to "https://unmu.app" if APP_PUBLIC_URL is
// unset. Used by password-reset emails to build the reset link.
func PublicAppURL() string {
	u := strings.TrimSpace(os.Getenv("APP_PUBLIC_URL"))
	if u == "" {
		return "https://unmu.app"
	}
	return strings.TrimRight(u, "/")
}

// randHex returns n bytes of crypto/rand encoded as hex (length 2n).
func randHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	const hex = "0123456789abcdef"
	out := make([]byte, n*2)
	for i, v := range b {
		out[i*2] = hex[v>>4]
		out[i*2+1] = hex[v&0x0f]
	}
	return string(out), nil
}

// encodeHeader applies a defensive encoded-word wrap when the header
// contains anything outside ASCII (provider names with diacritics etc.).
// Pure-ASCII inputs pass through unchanged.
func encodeHeader(s string) string {
	for _, r := range s {
		if r > 127 {
			return "=?UTF-8?B?" + base64StdString(s) + "?="
		}
	}
	return s
}

func base64StdString(s string) string {
	// Inline tiny base64 encoder to avoid pulling in encoding/base64 just
	// for headers. Standard-alphabet, no line breaks.
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	b := []byte(s)
	pad := (3 - len(b)%3) % 3
	for i := 0; i < pad; i++ {
		b = append(b, 0)
	}
	var out strings.Builder
	out.Grow((len(b) / 3) * 4)
	for i := 0; i < len(b); i += 3 {
		n := uint(b[i])<<16 | uint(b[i+1])<<8 | uint(b[i+2])
		out.WriteByte(alphabet[(n>>18)&0x3F])
		out.WriteByte(alphabet[(n>>12)&0x3F])
		out.WriteByte(alphabet[(n>>6)&0x3F])
		out.WriteByte(alphabet[n&0x3F])
	}
	r := out.String()
	if pad > 0 {
		r = r[:len(r)-pad] + strings.Repeat("=", pad)
	}
	return r
}

// HTML templates kept inline so the binary has no external file
// dependency. Color palette mirrors the app (cyan-600 + gold accent).
const verificationHTML = `<!doctype html><html><body style="margin:0;padding:32px 16px;background:#0a1019;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;color:#e6e8eb;">
  <div style="max-width:480px;margin:0 auto;background:linear-gradient(180deg,#0f1724 0%%,#0a1019 100%%);border:1px solid rgba(255,255,255,0.06);border-radius:16px;padding:36px 28px;">
    <div style="text-align:center;margin-bottom:24px;"><span style="display:inline-block;font-size:11px;letter-spacing:3px;color:#0891b2;font-weight:700;">UNMU · HALAL INVESTING</span></div>
    <h2 style="color:#fff;margin:0 0 8px;font-size:22px;font-weight:700;">Verify your email</h2>
    <p style="color:#94a3b8;margin:0 0 24px;font-size:14px;line-height:1.6;">Hi %s — enter this code in the app to confirm your account:</p>
    <div style="font-family:'SF Mono',Menlo,Consolas,monospace;font-size:32px;letter-spacing:10px;font-weight:700;color:#0891b2;text-align:center;background:rgba(8,145,178,0.08);border:1px solid rgba(8,145,178,0.2);padding:20px;border-radius:12px;">%s</div>
    <p style="color:#64748b;font-size:13px;margin:24px 0 0;line-height:1.6;">This code expires in 10 minutes. If you didn't request this, you can safely ignore this email — no account changes have been made.</p>
    <hr style="border:none;border-top:1px solid rgba(255,255,255,0.06);margin:28px 0 16px;">
    <p style="color:#475569;font-size:11px;margin:0;text-align:center;">UNMU · halal social investing · unmu.app</p>
  </div>
</body></html>`

const passwordResetHTML = `<!doctype html><html><body style="margin:0;padding:32px 16px;background:#0a1019;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;color:#e6e8eb;">
  <div style="max-width:480px;margin:0 auto;background:linear-gradient(180deg,#0f1724 0%%,#0a1019 100%%);border:1px solid rgba(255,255,255,0.06);border-radius:16px;padding:36px 28px;">
    <div style="text-align:center;margin-bottom:24px;"><span style="display:inline-block;font-size:11px;letter-spacing:3px;color:#0891b2;font-weight:700;">UNMU · HALAL INVESTING</span></div>
    <h2 style="color:#fff;margin:0 0 8px;font-size:22px;font-weight:700;">Reset your password</h2>
    <p style="color:#94a3b8;margin:0 0 24px;font-size:14px;line-height:1.6;">Hi %s — copy the link below and paste it into the UNMU app's reset screen to choose a new password.</p>
    <div style="text-align:center;margin:28px 0;"><a href="%s" style="display:inline-block;background:linear-gradient(180deg,#0891b2,#0e7490);color:#fff;text-decoration:none;padding:14px 32px;border-radius:10px;font-weight:600;font-size:14px;letter-spacing:0.3px;">Reset password</a></div>
    <p style="color:#64748b;font-size:12px;margin:0 0 8px;">Or copy this link and paste it into the UNMU app:</p>
    <p style="color:#0891b2;font-size:11px;word-break:break-all;font-family:monospace;margin:0;">%s</p>
    <p style="color:#64748b;font-size:13px;margin:24px 0 0;line-height:1.6;">This link expires in 1 hour. If you didn't request this, ignore this email — your password is unchanged.</p>
    <hr style="border:none;border-top:1px solid rgba(255,255,255,0.06);margin:28px 0 16px;">
    <p style="color:#475569;font-size:11px;margin:0;text-align:center;">UNMU · halal social investing · unmu.app</p>
  </div>
</body></html>`
