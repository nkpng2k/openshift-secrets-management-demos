#!/bin/bash
# Validates the full Vault PKI certificate chain and mTLS connectivity.
#
# Tests:
#   1. Vault Issuer readiness
#   2. Intermediate CA signed by Vault Root CA
#   3. Server leaf cert chains to root via intermediate
#   4. Client leaf cert chains to root via intermediate
#   5. Intermediate CA issuer CN (proves Vault signed it)
#   6. Leaf cert issuer CN (proves local intermediate issued it)
#   7. Direct leaf cert signed by Root CA (no intermediate)
#   8. Direct leaf cert issuer CN (proves Root CA signed it directly)
#   9. In-pod mTLS validation

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/vault-pki/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

VAULT_ISSUER_NS="vault-pki-demo-ns"
FAILED=0

echo "=== Vault PKI Chain of Trust Validation ==="
echo ""

# --- Test 1: Vault Issuer readiness ---
echo "=== Test 1: Vault PKI Issuer Status ==="
ISSUER_READY=$(oc get issuer vault-pki-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [[ "$ISSUER_READY" == "True" ]]; then
  echo "PASS: Vault PKI Issuer is ready"
else
  echo "FAIL: Vault PKI Issuer is not ready"
  FAILED=1
fi

echo ""

# Load certificates for verification
ROOT_CA=$(cat $SCRIPT_DIR/config/tmp_root_ca.crt)
INTERMEDIATE_CA=$(oc get secret intermediate-ca-secret -n $VAULT_ISSUER_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)
SERVER_CERT=$(oc get secret server-tls -n $VAULT_ISSUER_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)
CLIENT_CERT=$(oc get secret client-tls -n $VAULT_ISSUER_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)

# --- Test 2: Intermediate CA signed by Vault Root CA ---
echo "=== Test 2: Certificate Chain — Root CA -> Intermediate CA ==="
VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") <(echo "$INTERMEDIATE_CA") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Intermediate CA is signed by Vault Root CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# --- Test 3: Server leaf cert chains to root via intermediate ---
echo "=== Test 3: Certificate Chain — Root -> Intermediate -> Server Leaf ==="
VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") -untrusted <(echo "$INTERMEDIATE_CA") <(echo "$SERVER_CERT") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Server leaf cert chains to Root CA via Intermediate CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# --- Test 4: Client leaf cert chains to root via intermediate ---
echo "=== Test 4: Certificate Chain — Root -> Intermediate -> Client Leaf ==="
VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") -untrusted <(echo "$INTERMEDIATE_CA") <(echo "$CLIENT_CERT") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Client leaf cert chains to Root CA via Intermediate CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# --- Test 5: Intermediate CA issuer CN (Vault signed it) ---
echo "=== Test 5: Intermediate CA Issuer (should be Vault Root CA) ==="
ISSUER_CN=$(echo "$INTERMEDIATE_CA" | openssl x509 -noout -issuer 2>/dev/null)
if echo "$ISSUER_CN" | grep -q "Vault PKI Demo Root CA"; then
  echo "PASS: Intermediate CA was signed by Vault Root CA"
  echo "  $ISSUER_CN"
else
  echo "FAIL: Unexpected issuer: $ISSUER_CN"
  FAILED=1
fi

echo ""

# --- Test 6: Leaf cert issuer CN (local intermediate issued it) ---
echo "=== Test 6: Leaf Certificate Issuer (should be Intermediate CA) ==="
LEAF_ISSUER=$(echo "$SERVER_CERT" | openssl x509 -noout -issuer 2>/dev/null)
if echo "$LEAF_ISSUER" | grep -q "Vault PKI Demo Intermediate CA"; then
  echo "PASS: Server leaf cert was issued by on-cluster Intermediate CA"
  echo "  $LEAF_ISSUER"
else
  echo "FAIL: Unexpected issuer: $LEAF_ISSUER"
  FAILED=1
fi

echo ""

# --- Test 7: Direct leaf cert signed by Root CA ---
echo "=== Test 7: Direct Leaf Certificate (signed by Vault Root CA) ==="
DIRECT_CERT=$(oc get secret vault-direct-tls -n $VAULT_ISSUER_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)
VERIFY_RESULT=$(openssl verify -CAfile <(echo "$ROOT_CA") <(echo "$DIRECT_CERT") 2>&1)
if echo "$VERIFY_RESULT" | grep -q "OK"; then
  echo "PASS: Direct leaf cert is signed by Vault Root CA"
else
  echo "FAIL: $VERIFY_RESULT"
  FAILED=1
fi

echo ""

# --- Test 8: Direct leaf cert issuer CN ---
echo "=== Test 8: Direct Leaf Issuer (should be Vault Root CA, no intermediate) ==="
DIRECT_ISSUER=$(echo "$DIRECT_CERT" | openssl x509 -noout -issuer 2>/dev/null)
if echo "$DIRECT_ISSUER" | grep -q "Vault PKI Demo Root CA"; then
  echo "PASS: Direct leaf cert was signed directly by Vault Root CA"
  echo "  $DIRECT_ISSUER"
else
  echo "FAIL: Unexpected issuer: $DIRECT_ISSUER"
  FAILED=1
fi

echo ""

# --- Test 9: In-pod mTLS validation ---
echo "=== Test 7: In-Pod mTLS Validation ==="
CLIENT_POD=$(oc get pods -n $VAULT_ISSUER_NS -l app=mtls-client --no-headers | awk '{print $1}')

oc exec $CLIENT_POD -n $VAULT_ISSUER_NS -- /scripts/validate_mtls.sh
if [[ $? -ne 0 ]]; then
  FAILED=1
fi

echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "=== All Vault PKI validations PASSED ==="
else
  echo "=== Some validations FAILED ==="
  exit 1
fi
