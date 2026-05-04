#!/bin/bash

# mTLS validation script - runs inside the client pod
# Uses mounted certificates and trust bundle to validate the chain of trust

SERVER_URL="https://mtls-server.DEMO_NS.svc.cluster.local"
CLIENT_CERT="/etc/client-tls/tls.crt"
CLIENT_KEY="/etc/client-tls/tls.key"
CA_BUNDLE="/etc/trust/ca-bundle.crt"

FAILED=0

echo "=== mTLS Validation ==="
echo ""

# Test 1: mTLS connection with client cert + CA bundle
echo "=== Test 1: mTLS Connection (client cert + CA bundle) ==="
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --cert "$CLIENT_CERT" \
  --key "$CLIENT_KEY" \
  --cacert "$CA_BUNDLE" \
  "$SERVER_URL")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "PASS: mTLS request returned HTTP $HTTP_CODE"
else
  echo "FAIL: mTLS request returned HTTP $HTTP_CODE (expected 200)"
  FAILED=1
fi

echo ""

# Test 2: Connection WITHOUT client cert (should be rejected by server)
echo "=== Test 2: No Client Cert (should be rejected) ==="
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --cacert "$CA_BUNDLE" \
  "$SERVER_URL" 2>/dev/null)

if [[ "$HTTP_CODE" == "400" ]] || [[ "$HTTP_CODE" == "000" ]]; then
  echo "PASS: Request without client cert was rejected (HTTP $HTTP_CODE)"
else
  echo "FAIL: Request without client cert returned HTTP $HTTP_CODE (expected 400 or connection failure)"
  FAILED=1
fi

echo ""

# Test 3: Connection WITHOUT CA bundle (should fail TLS verification)
echo "=== Test 3: No CA Bundle (should fail TLS verification) ==="
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --cert "$CLIENT_CERT" \
  --key "$CLIENT_KEY" \
  "$SERVER_URL" 2>/dev/null)

if [[ "$HTTP_CODE" == "000" ]]; then
  echo "PASS: Request without CA bundle failed TLS verification (HTTP $HTTP_CODE)"
else
  echo "FAIL: Request without CA bundle returned HTTP $HTTP_CODE (expected connection failure)"
  FAILED=1
fi

echo ""

# Test 4: Full mTLS request showing response body
echo "=== Test 4: mTLS Response Body ==="
RESPONSE=$(curl -s \
  --cert "$CLIENT_CERT" \
  --key "$CLIENT_KEY" \
  --cacert "$CA_BUNDLE" \
  "$SERVER_URL")

if [[ "$RESPONSE" == *"Hello mTLS"* ]]; then
  echo "PASS: Server responded with: $RESPONSE"
else
  echo "FAIL: Unexpected response: $RESPONSE"
  FAILED=1
fi

echo ""

# Test 5: Display certificate chain details
echo "=== Certificate Chain Details ==="
echo | openssl s_client \
  -cert "$CLIENT_CERT" \
  -key "$CLIENT_KEY" \
  -CAfile "$CA_BUNDLE" \
  -connect mtls-server.DEMO_NS.svc.cluster.local:443 \
  -servername mtls-server.DEMO_NS.svc.cluster.local \
  2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null

echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "=== All mTLS validations passed ==="
else
  echo "=== Some mTLS validations FAILED ==="
  exit 1
fi
