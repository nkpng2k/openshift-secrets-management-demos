#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

DEMO_NS="trust-manager-demo-ns"
CONSUMER_NS="trust-manager-consumer-ns"
FAILED=0

echo "=== Chain of Trust Validation ==="
echo ""

# --- Cluster-side checks ---

# Test 1: Verify intermediate CA is signed by root CA
echo "=== Test 1: Certificate Chain - Root -> Intermediate ==="
ROOT_CA=$(oc get secret root-ca-secret -n $DEMO_NS -o jsonpath='{.data.ca\.crt}' | base64 -d)
INTERMEDIATE_CA=$(oc get secret intermediate-ca-secret -n $DEMO_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)

VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") <(echo "$INTERMEDIATE_CA") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Intermediate CA is signed by Root CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# Test 2: Verify server leaf cert chains to root via intermediate
echo "=== Test 2: Certificate Chain - Root -> Intermediate -> Server Leaf ==="
SERVER_CERT=$(oc get secret server-tls -n $DEMO_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)

VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") -untrusted <(echo "$INTERMEDIATE_CA") <(echo "$SERVER_CERT") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Server leaf cert chains to Root CA via Intermediate CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# Test 3: Verify client leaf cert chains to root via intermediate
echo "=== Test 3: Certificate Chain - Root -> Intermediate -> Client Leaf ==="
CLIENT_CERT=$(oc get secret client-tls -n $DEMO_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)

VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") -untrusted <(echo "$INTERMEDIATE_CA") <(echo "$CLIENT_CERT") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Client leaf cert chains to Root CA via Intermediate CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# Test 4: Trust bundle ConfigMap exists in demo namespace
echo "=== Test 4: Trust Bundle in Demo Namespace ==="
if oc get configmap demo-trust-bundle -n $DEMO_NS &>/dev/null; then
  echo "PASS: ConfigMap demo-trust-bundle exists in $DEMO_NS"
else
  echo "FAIL: ConfigMap demo-trust-bundle not found in $DEMO_NS"
  FAILED=1
fi

echo ""

# Test 5: Trust bundle ConfigMap exists in consumer namespace
echo "=== Test 5: Trust Bundle in Consumer Namespace ==="
if oc get configmap demo-trust-bundle -n $CONSUMER_NS &>/dev/null; then
  echo "PASS: ConfigMap demo-trust-bundle exists in $CONSUMER_NS"
else
  echo "FAIL: ConfigMap demo-trust-bundle not found in $CONSUMER_NS"
  FAILED=1
fi

echo ""

# Test 6: Trust bundle contains expected CA certificates
echo "=== Test 6: Trust Bundle Contents ==="
BUNDLE_CONTENT=$(oc get configmap demo-trust-bundle -n $DEMO_NS -o jsonpath='{.data.ca-bundle\.crt}')
CERT_COUNT=$(echo "$BUNDLE_CONTENT" | grep -c "BEGIN CERTIFICATE")

if [[ $CERT_COUNT -ge 3 ]]; then
  echo "PASS: Trust bundle contains $CERT_COUNT certificates (intermediate CA + root CA + default CAs)"
else
  echo "FAIL: Trust bundle contains only $CERT_COUNT certificates (expected at least 3)"
  FAILED=1
fi

echo ""

# --- mTLS checks (executed inside the client pod) ---

echo "=== Running mTLS validation from client pod ==="
echo ""

CLIENT_POD=$(oc get pods -n $DEMO_NS -l app=mtls-client --no-headers | awk '{print $1}')

oc exec $CLIENT_POD -n $DEMO_NS -- /scripts/validate_mtls.sh
if [[ $? -ne 0 ]]; then
  FAILED=1
fi

echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "=== All chain of trust validations PASSED ==="
else
  echo "=== Some validations FAILED ==="
  exit 1
fi
