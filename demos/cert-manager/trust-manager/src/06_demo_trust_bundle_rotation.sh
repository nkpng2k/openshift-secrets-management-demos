#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

CA_NS="cert-manager"
SERVER_NS="trust-manager-server-ns"
CLIENT_NS="trust-manager-client-ns"

echo "=== Trust Bundle Rotation Demo ==="
echo ""
echo "This demo triggers an intermediate CA key rotation and shows that:"
echo "  1. cert-manager re-issues the intermediate CA with a new key"
echo "  2. trust-manager automatically updates the trust bundle ConfigMap"
echo "  3. cert-manager re-issues leaf certificates signed by the new key"
echo "  4. mTLS communication continues to work end-to-end"
echo ""

# ── Capture "before" state ──

BEFORE_FINGERPRINT=$(oc get secret intermediate-ca-secret -n $CA_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -fingerprint -sha256 -noout 2>/dev/null)
BEFORE_SERIAL=$(oc get secret intermediate-ca-secret -n $CA_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
BEFORE_SERVER_SERIAL=$(oc get secret server-tls -n $SERVER_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
BEFORE_CLIENT_SERIAL=$(oc get secret client-tls -n $CLIENT_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
BEFORE_SERVER_CM=$(oc get configmap demo-trust-bundle -n $SERVER_NS \
  -o jsonpath='{.metadata.resourceVersion}')
BEFORE_CLIENT_CM=$(oc get configmap demo-trust-bundle -n $CLIENT_NS \
  -o jsonpath='{.metadata.resourceVersion}')

echo "=== Before Rotation ==="
echo "  Intermediate CA: $BEFORE_SERIAL"
echo "  Server leaf:     $BEFORE_SERVER_SERIAL"
echo "  Client leaf:     $BEFORE_CLIENT_SERIAL"
echo "  Trust bundle rv: $BEFORE_SERVER_CM (server-ns), $BEFORE_CLIENT_CM (client-ns)"
echo ""

# ── Trigger rotation ──

echo "Deleting intermediate-ca-secret to trigger key rotation..."
oc delete secret intermediate-ca-secret -n $CA_NS
echo ""

# Wait for cert-manager to re-issue the intermediate CA
echo "Waiting for cert-manager to re-issue intermediate CA..."
TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CURRENT_SERIAL=$(oc get secret intermediate-ca-secret -n $CA_NS \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -serial -noout 2>/dev/null)

  if [[ -n "$CURRENT_SERIAL" && "$CURRENT_SERIAL" != "$BEFORE_SERIAL" ]]; then
    echo "Intermediate CA re-issued with new key."
    break
  fi

  printf "."
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done
echo ""

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "ERROR: Timed out waiting for intermediate CA re-issuance after ${TIMEOUT}s"
  oc describe certificate intermediate-ca -n $CA_NS
  exit 1
fi

# ── Wait for trust bundle update ──

echo "Waiting for trust-manager to update the trust bundle..."
for NS in $SERVER_NS $CLIENT_NS; do
  if [[ "$NS" == "$SERVER_NS" ]]; then
    BEFORE_VER=$BEFORE_SERVER_CM
  else
    BEFORE_VER=$BEFORE_CLIENT_CM
  fi

  TIMEOUT=60
  ELAPSED=0
  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    CURRENT_VER=$(oc get configmap demo-trust-bundle -n $NS \
      -o jsonpath='{.metadata.resourceVersion}')

    if [[ "$CURRENT_VER" != "$BEFORE_VER" ]]; then
      echo "  Trust bundle updated in $NS (rv: $BEFORE_VER -> $CURRENT_VER)"
      break
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
  done

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "  WARNING: Trust bundle did not update in $NS within ${TIMEOUT}s"
  fi
done

echo ""

# ── Wait for leaf certificates to be re-issued ──

echo "Waiting for leaf certificates to be re-issued with the new intermediate key..."
echo "(Leaf certs renew every ~10 minutes)"

LEAF_NAMES=("server-tls" "client-tls")
LEAF_NSS=("$SERVER_NS" "$CLIENT_NS")
LEAF_BEFORE_SERIALS=("$BEFORE_SERVER_SERIAL" "$BEFORE_CLIENT_SERIAL")

TIMEOUT=600
ELAPSED=0
BOTH_RENEWED=false

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  ALL_DONE=true
  for i in 0 1; do
    CURRENT=$(oc get secret ${LEAF_NAMES[$i]} -n ${LEAF_NSS[$i]} \
      -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)

    if [[ "$CURRENT" == "${LEAF_BEFORE_SERIALS[$i]}" ]]; then
      ALL_DONE=false
    fi
  done

  if $ALL_DONE; then
    BOTH_RENEWED=true
    echo "Both leaf certificates have been re-issued."
    break
  fi

  printf "."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done
echo ""

if ! $BOTH_RENEWED; then
  echo "WARNING: Not all leaf certs renewed within ${TIMEOUT}s. Continuing with validation..."
fi

# ── Wait for kubelet ConfigMap volume sync ──

echo "Waiting for kubelet to sync updated volumes to pods (60s)..."
wait_spinner 60

# ── Restart server to pick up new trust bundle ──

echo "Restarting server to load updated certificates..."
oc rollout restart deployment/mtls-server -n $SERVER_NS
oc wait --for=condition=Available deployment/mtls-server -n $SERVER_NS --timeout=120s
echo ""

# ── Capture "after" state ──

AFTER_SERIAL=$(oc get secret intermediate-ca-secret -n $CA_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
AFTER_SERVER_SERIAL=$(oc get secret server-tls -n $SERVER_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
AFTER_CLIENT_SERIAL=$(oc get secret client-tls -n $CLIENT_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
AFTER_SERVER_CM=$(oc get configmap demo-trust-bundle -n $SERVER_NS \
  -o jsonpath='{.metadata.resourceVersion}')
AFTER_CLIENT_CM=$(oc get configmap demo-trust-bundle -n $CLIENT_NS \
  -o jsonpath='{.metadata.resourceVersion}')

echo "=== After Rotation ==="
echo "  Intermediate CA: $AFTER_SERIAL"
echo "  Server leaf:     $AFTER_SERVER_SERIAL"
echo "  Client leaf:     $AFTER_CLIENT_SERIAL"
echo "  Trust bundle rv: $AFTER_SERVER_CM (server-ns), $AFTER_CLIENT_CM (client-ns)"
echo ""

# ── Verify rotation results ──

FAILED=0

if [[ "$BEFORE_SERIAL" != "$AFTER_SERIAL" ]]; then
  echo "PASS: Intermediate CA was re-issued (serial changed)"
else
  echo "FAIL: Intermediate CA serial did not change"
  FAILED=1
fi

if [[ "$BEFORE_SERVER_CM" != "$AFTER_SERVER_CM" ]]; then
  echo "PASS: Trust bundle was automatically updated"
else
  echo "FAIL: Trust bundle was not updated"
  FAILED=1
fi

if [[ "$BEFORE_SERVER_SERIAL" != "$AFTER_SERVER_SERIAL" ]]; then
  echo "PASS: Server leaf cert was re-issued with new key"
else
  echo "WARN: Server leaf cert was not yet re-issued"
fi

if [[ "$BEFORE_CLIENT_SERIAL" != "$AFTER_CLIENT_SERIAL" ]]; then
  echo "PASS: Client leaf cert was re-issued with new key"
else
  echo "WARN: Client leaf cert was not yet re-issued"
fi

echo ""

# ── Re-validate mTLS ──

echo "=== Re-validating mTLS after rotation ==="
CLIENT_POD=$(oc get pods -n $CLIENT_NS -l app=mtls-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
oc exec $CLIENT_POD -n $CLIENT_NS -- /scripts/validate_mtls.sh

if [[ $? -eq 0 ]]; then
  echo ""
  echo "=== Rotation Demo Complete ==="
  echo "The intermediate CA was rotated with a new key. cert-manager re-issued"
  echo "leaf certificates, and trust-manager automatically updated the trust"
  echo "bundle. mTLS communication continues to work end-to-end."
else
  echo ""
  echo "WARNING: mTLS validation failed after rotation."
  echo "The server may need additional time to pick up the new certificates."
  echo "Try: oc rollout restart deployment/mtls-server -n $SERVER_NS"
  FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
