package services

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"strings"
	"testing"
	"time"
)

// testChain is a root → intermediate → leaf chain shaped like Apple's.
type testChain struct {
	root            *x509.Certificate
	x5c             []string
	leafKey         *ecdsa.PrivateKey
	intermediateKey *ecdsa.PrivateKey
}

func newTestCert(t *testing.T, cn string, parent *x509.Certificate, parentKey *ecdsa.PrivateKey, ca bool, oid asn1.ObjectIdentifier) (*x509.Certificate, *ecdsa.PrivateKey) {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: cn},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		IsCA: ca, BasicConstraintsValid: true,
		KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
	}
	if oid != nil {
		tmpl.ExtraExtensions = []pkix.Extension{{Id: oid, Value: []byte{0x05, 0x00}}}
	}
	if parent == nil {
		parent, parentKey = tmpl, key
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, parent, &key.PublicKey, parentKey)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(der)
	return cert, key
}

func newTestChain(t *testing.T, leafOID asn1.ObjectIdentifier) testChain {
	root, rootKey := newTestCert(t, "root", nil, nil, true, nil)
	inter, interKey := newTestCert(t, "inter", root, rootKey, true, oidAppleIntermediate)
	leaf, leafKey := newTestCert(t, "leaf", inter, interKey, false, leafOID)
	enc := func(c *x509.Certificate) string { return base64.StdEncoding.EncodeToString(c.Raw) }
	return testChain{root: root, x5c: []string{enc(leaf), enc(inter), enc(root)}, leafKey: leafKey, intermediateKey: interKey}
}

func (c testChain) sign(t *testing.T, payload any) string {
	t.Helper()
	h, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": c.x5c})
	p, _ := json.Marshal(payload)
	input := base64.RawURLEncoding.EncodeToString(h) + "." + base64.RawURLEncoding.EncodeToString(p)
	digest := sha256.Sum256([]byte(input))
	r, s, _ := ecdsa.Sign(rand.Reader, c.leafKey, digest[:])
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return input + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func (c testChain) verifier() *AppleNotificationVerifier {
	roots := x509.NewCertPool()
	roots.AddCert(c.root)
	return &AppleNotificationVerifier{roots: roots, bundleID: "com.test.app", now: time.Now}
}

func refundPayload(c testChain, t *testing.T, bundle string) map[string]any {
	txn := c.sign(t, map[string]any{"transactionId": "T1", "originalTransactionId": "T1",
		"productId": "com.unmu.access.t2.month", "bundleId": bundle})
	return map[string]any{"notificationType": "REFUND",
		"data": map[string]any{"bundleId": bundle, "environment": "Sandbox", "signedTransactionInfo": txn}}
}

func TestAppleNotification_ValidRefund(t *testing.T) {
	c := newTestChain(t, oidAppleLeaf)
	n, err := c.verifier().Parse(c.sign(t, refundPayload(c, t, "com.test.app")))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if n.Type != "REFUND" || n.Transaction == nil || n.Transaction.TransactionID != "T1" ||
		n.Transaction.ProductID != "com.unmu.access.t2.month" {
		t.Fatalf("unexpected %+v %+v", n, n.Transaction)
	}
}

func TestAppleNotification_Rejections(t *testing.T) {
	good := newTestChain(t, oidAppleLeaf)
	other := newTestChain(t, oidAppleLeaf)
	noOID := newTestChain(t, nil)
	tampered := good.sign(t, refundPayload(good, t, "com.test.app"))
	parts := strings.Split(tampered, ".")
	parts[1] = base64.RawURLEncoding.EncodeToString([]byte(`{"notificationType":"REFUND"}`))

	cases := map[string]string{
		"chain from another root": other.sign(t, refundPayload(other, t, "com.test.app")),
		"leaf without Apple OID":  noOID.sign(t, refundPayload(noOID, t, "com.test.app")),
		"payload changed":         strings.Join(parts, "."),
		"other app's bundle":      good.sign(t, refundPayload(good, t, "com.other.app")),
		"not a JWS":               "abc",
	}
	for name, jws := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := good.verifier().Parse(jws); err == nil {
				t.Fatal("must be rejected")
			}
		})
	}
	t.Run("leaf without OID verified against its own root", func(t *testing.T) {
		if _, err := noOID.verifier().Parse(noOID.sign(t, refundPayload(noOID, t, "com.test.app"))); err == nil {
			t.Fatal("must be rejected")
		}
	})
}

func TestNewAppleNotificationVerifier_EmbeddedRoot(t *testing.T) {
	v, err := NewAppleNotificationVerifier()
	if err != nil || v.bundleID == "" {
		t.Fatalf("got %v %v", v, err)
	}
}
