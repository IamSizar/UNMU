// apple_notifications.go — verifies App Store Server Notifications v2.
//
// Apple POSTs {"signedPayload": "<JWS>"}. The JWS (ES256) carries its
// certificate chain in the x5c header; we accept it only when that chain
// leads to Apple Root CA - G3 (embedded below, fetched from
// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer, SHA-256
// 63:34:3A:BF:…:91:79), the intermediate and leaf carry Apple's marker
// OIDs, the signature is valid and the bundle id is ours. The transaction
// inside (signedTransactionInfo) is a second JWS checked the same way.
// Used for refunds: docs/payments/REFUNDS_PLAN.md.
package services

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"
)

//go:embed certs/AppleRootCA-G3.pem
var appleRootCAG3PEM []byte

// Apple's marker OIDs: the WWDR intermediate and the App Store receipt
// signing leaf.
var (
	oidAppleIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
	oidAppleLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
)

// AppleNotification is the verified part of a notification we act on.
type AppleNotification struct {
	Type        string // e.g. REFUND, REVOKE, REFUND_REVERSED
	Subtype     string
	Environment string                        // Production | Sandbox
	Transaction *AppleNotificationTransaction // nil when the type carries none
}

// AppleNotificationTransaction is the verified signedTransactionInfo.
type AppleNotificationTransaction struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	ProductID             string `json:"productId"`
	BundleID              string `json:"bundleId"`
}

// AppleNotificationVerifier checks notification signatures.
type AppleNotificationVerifier struct {
	roots    *x509.CertPool
	bundleID string
	now      func() time.Time
}

// NewAppleNotificationVerifier trusts Apple Root CA - G3 and the app's
// bundle id (APPLE_BUNDLE_ID, default the iOS app's).
func NewAppleNotificationVerifier() (*AppleNotificationVerifier, error) {
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(appleRootCAG3PEM) {
		return nil, errors.New("apple-notifications: embedded root certificate is invalid")
	}
	bundleID := strings.TrimSpace(os.Getenv("APPLE_BUNDLE_ID"))
	if bundleID == "" {
		bundleID = defaultAppleBundleID
	}
	return &AppleNotificationVerifier{roots: roots, bundleID: bundleID, now: time.Now}, nil
}

// Parse verifies a signedPayload and returns the notification.
func (v *AppleNotificationVerifier) Parse(signedPayload string) (*AppleNotification, error) {
	var body struct {
		NotificationType string `json:"notificationType"`
		Subtype          string `json:"subtype"`
		Data             struct {
			BundleID              string `json:"bundleId"`
			Environment           string `json:"environment"`
			SignedTransactionInfo string `json:"signedTransactionInfo"`
		} `json:"data"`
	}
	if err := v.verifyJWS(signedPayload, &body); err != nil {
		return nil, err
	}
	if body.Data.BundleID != v.bundleID {
		return nil, fmt.Errorf("apple-notifications: bundle %q is not ours", body.Data.BundleID)
	}
	n := &AppleNotification{Type: body.NotificationType, Subtype: body.Subtype, Environment: body.Data.Environment}
	if body.Data.SignedTransactionInfo == "" {
		return n, nil
	}
	var txn AppleNotificationTransaction
	if err := v.verifyJWS(body.Data.SignedTransactionInfo, &txn); err != nil {
		return nil, fmt.Errorf("transaction: %w", err)
	}
	if txn.BundleID != v.bundleID {
		return nil, fmt.Errorf("apple-notifications: transaction bundle %q is not ours", txn.BundleID)
	}
	n.Transaction = &txn
	return n, nil
}

// verifyJWS checks the chain, OIDs and ES256 signature, then decodes the
// payload into out.
func (v *AppleNotificationVerifier) verifyJWS(jws string, out any) error {
	parts := strings.Split(strings.TrimSpace(jws), ".")
	if len(parts) != 3 {
		return errors.New("apple-notifications: not a JWS")
	}
	leaf, err := v.verifiedLeaf(parts[0])
	if err != nil {
		return err
	}
	if err := verifyES256(leaf, parts[0]+"."+parts[1], parts[2]); err != nil {
		return err
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return errors.New("apple-notifications: bad payload encoding")
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return fmt.Errorf("apple-notifications: decode payload: %w", err)
	}
	return nil
}

// verifiedLeaf reads the JWS header and returns its leaf certificate
// once the x5c chain verifies to the trusted root with Apple's OIDs.
func (v *AppleNotificationVerifier) verifiedLeaf(rawHeader string) (*x509.Certificate, error) {
	var header struct {
		Alg string   `json:"alg"`
		X5c []string `json:"x5c"`
	}
	hb, err := base64.RawURLEncoding.DecodeString(rawHeader)
	if err != nil || json.Unmarshal(hb, &header) != nil {
		return nil, errors.New("apple-notifications: bad header")
	}
	if header.Alg != "ES256" || len(header.X5c) != 3 { // Apple sends leaf, intermediate, root
		return nil, errors.New("apple-notifications: unexpected alg or missing certificate chain")
	}
	certs := make([]*x509.Certificate, 0, len(header.X5c))
	for _, c := range header.X5c {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return nil, errors.New("apple-notifications: bad certificate encoding")
		}
		cert, err := x509.ParseCertificate(der)
		if err != nil {
			return nil, fmt.Errorf("apple-notifications: parse certificate: %w", err)
		}
		certs = append(certs, cert)
	}
	intermediates := x509.NewCertPool()
	for _, c := range certs[1:] {
		intermediates.AddCert(c)
	}
	chains, err := certs[0].Verify(x509.VerifyOptions{
		Roots: v.roots, Intermediates: intermediates, CurrentTime: v.now(),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	})
	if err != nil || len(chains) == 0 || len(chains[0]) < 3 {
		return nil, errors.New("apple-notifications: certificate chain is not Apple's")
	}
	if !hasExtension(chains[0][0], oidAppleLeaf) || !hasExtension(chains[0][1], oidAppleIntermediate) {
		return nil, errors.New("apple-notifications: certificate is missing Apple's marker")
	}
	return chains[0][0], nil
}

func hasExtension(c *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}

// verifyES256 checks a JWS ES256 signature (raw 64-byte r||s).
func verifyES256(leaf *x509.Certificate, signingInput, rawSig string) error {
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	sig, err := base64.RawURLEncoding.DecodeString(rawSig)
	if !ok || err != nil || len(sig) != 64 {
		return errors.New("apple-notifications: bad signature")
	}
	digest := sha256.Sum256([]byte(signingInput))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, digest[:], r, s) {
		return errors.New("apple-notifications: signature does not verify")
	}
	return nil
}
