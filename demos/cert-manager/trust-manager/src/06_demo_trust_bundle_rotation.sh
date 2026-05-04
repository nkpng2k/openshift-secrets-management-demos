#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

DEMO_NS="trust-manager-demo-ns"
CONSUMER_NS="trust-manager-consumer-ns"

echo "=== Trust Bundle Rotation Demo ==="
echo ""
echo "This demo waits for cert-manager to naturally renew the intermediate CA"
echo "certificate (duration: 1h10m, renewBefore: 1h) and shows that trust-manager"
echo "automatically updates the trust bundle ConfigMap in all target namespaces."
echo ""

# Capture "before" state
BEFORE_FINGERPRINT=$(oc get secret intermediate-ca-secret -n $DEMO_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -fingerprint -sha256 -noout 2>/dev/null)
BEFORE_SERIAL=$(oc get secret intermediate-ca-secret -n $DEMO_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
BEFORE_CM_VERSION=$(oc get configmap demo-trust-bundle -n $DEMO_NS \
  -o jsonpath='{.metadata.resourceVersion}')

echo "=== Before Rotation ==="
echo "Intermediate CA: $BEFORE_FINGERPRINT"
echo "Serial: $BEFORE_SERIAL"
echo "Trust bundle ConfigMap resourceVersion: $BEFORE_CM_VERSION"

# Calculate expected renewal time
NOT_AFTER=$(oc get secret intermediate-ca-secret -n $DEMO_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -enddate -noout 2>/dev/null | sed 's/notAfter=//')
echo "Certificate expires: $NOT_AFTER"
echo "Renewal expected ~5 minutes before expiry."
echo ""

# Poll for intermediate CA renewal
echo "Waiting for intermediate CA to be renewed..."
TIMEOUT=900
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CURRENT_SERIAL=$(oc get secret intermediate-ca-secret -n $DEMO_NS \
    -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)

  if [[ "$CURRENT_SERIAL" != "$BEFORE_SERIAL" ]]; then
    echo ""
    echo "Intermediate CA certificate renewed!"
    break
  fi

  printf "."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo ""
  echo "ERROR: Timed out waiting for certificate renewal after ${TIMEOUT}s"
  oc describe certificate intermediate-ca -n $DEMO_NS
  exit 1
fi

# Wait for trust bundle ConfigMap to update
echo ""
echo "Waiting for trust bundle ConfigMap to update..."
TIMEOUT=60
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CURRENT_CM_VERSION=$(oc get configmap demo-trust-bundle -n $DEMO_NS \
    -o jsonpath='{.metadata.resourceVersion}')

  if [[ "$CURRENT_CM_VERSION" != "$BEFORE_CM_VERSION" ]]; then
    echo "Trust bundle ConfigMap updated in $DEMO_NS"
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "WARNING: Trust bundle ConfigMap did not update in $DEMO_NS within ${TIMEOUT}s"
fi

# Capture "after" state
AFTER_FINGERPRINT=$(oc get secret intermediate-ca-secret -n $DEMO_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -fingerprint -sha256 -noout 2>/dev/null)
AFTER_SERIAL=$(oc get secret intermediate-ca-secret -n $DEMO_NS \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -serial -noout 2>/dev/null)
AFTER_CM_VERSION=$(oc get configmap demo-trust-bundle -n $DEMO_NS \
  -o jsonpath='{.metadata.resourceVersion}')
CONSUMER_CM_VERSION=$(oc get configmap demo-trust-bundle -n $CONSUMER_NS \
  -o jsonpath='{.metadata.resourceVersion}')

echo ""
echo "=== After Rotation ==="
echo "Intermediate CA: $AFTER_FINGERPRINT"
echo "Serial: $AFTER_SERIAL"
echo "Trust bundle ConfigMap resourceVersion ($DEMO_NS): $AFTER_CM_VERSION"
echo "Trust bundle ConfigMap resourceVersion ($CONSUMER_NS): $CONSUMER_CM_VERSION"
echo ""

if [[ "$BEFORE_SERIAL" != "$AFTER_SERIAL" ]]; then
  echo "PASS: Intermediate CA certificate was renewed (serial changed)"
else
  echo "FAIL: Intermediate CA serial did not change"
  exit 1
fi

if [[ "$BEFORE_CM_VERSION" != "$AFTER_CM_VERSION" ]]; then
  echo "PASS: Trust bundle ConfigMap was automatically updated"
else
  echo "FAIL: Trust bundle ConfigMap was not updated"
  exit 1
fi

# Wait for kubelet to sync the ConfigMap volume in the pods
echo ""
echo "Waiting for kubelet ConfigMap volume sync (60s)..."
wait_spinner 60

# Re-validate mTLS connectivity after rotation
echo ""
echo "=== Re-validating mTLS after rotation ==="
CLIENT_POD=$(oc get pods -n $DEMO_NS -l app=mtls-client --no-headers | awk '{print $1}')
oc exec $CLIENT_POD -n $DEMO_NS -- /scripts/validate_mtls.sh

if [[ $? -eq 0 ]]; then
  echo ""
  echo "=== Rotation Demo Complete ==="
  echo "The trust bundle was automatically updated when the intermediate CA was"
  echo "renewed, and mTLS communication continues to work with the new certificates."
else
  echo ""
  echo "WARNING: mTLS validation failed after rotation."
  echo "This may be expected if the server has not yet picked up the new certificates."
  echo "Try restarting the server deployment: oc rollout restart deployment/mtls-server -n $DEMO_NS"
fi
