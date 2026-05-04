#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

DEMO_NS="trust-manager-demo-ns"
CONSUMER_NS="trust-manager-consumer-ns"

# Verify the Bundle CRD exists (trust-manager is running)
echo "Verifying trust-manager is available..."
if ! oc get crd bundles.trust.cert-manager.io &>/dev/null; then
  echo "ERROR: Bundle CRD not found. Ensure TechPreviewNoUpgrade FeatureGate is enabled"
  echo "       and the cert-manager operator has deployed trust-manager."
  echo ""
  echo "Check: oc get crd bundles.trust.cert-manager.io"
  echo "Check: oc get pods -n cert-manager | grep trust-manager"
  exit 1
fi
echo "Bundle CRD found."

# Create consumer namespace to demonstrate cross-namespace distribution
oc new-project $CONSUMER_NS

# Label both namespaces for the trust bundle selector
oc label namespace $DEMO_NS trust-manager-demo=true --overwrite
oc label namespace $CONSUMER_NS trust-manager-demo=true --overwrite

# Substitute placeholders and apply trust bundle
sed \
  -e "s|DEMO_NS|$DEMO_NS|g" \
  $SCRIPT_DIR/config/trust_bundle.yaml > $SCRIPT_DIR/config/tmp_trust_bundle.yaml

oc apply -f $SCRIPT_DIR/config/tmp_trust_bundle.yaml

# Wait for the trust bundle ConfigMap to appear in both namespaces
echo "Waiting for trust bundle ConfigMap distribution..."
for NS in $DEMO_NS $CONSUMER_NS; do
  TIMEOUT=60
  ELAPSED=0
  while ! oc get configmap demo-trust-bundle -n $NS &>/dev/null; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
      echo "ERROR: Trust bundle ConfigMap not found in $NS after ${TIMEOUT}s"
      oc get bundle demo-trust-bundle -o yaml
      exit 1
    fi
  done
  echo "  ConfigMap demo-trust-bundle found in $NS"
done

echo ""
echo "Trust bundle distributed successfully."
echo ""
echo "Trust bundle contents (number of PEM certificates):"
CERT_COUNT=$(oc get configmap demo-trust-bundle -n $DEMO_NS -o jsonpath='{.data.ca-bundle\.crt}' | grep -c "BEGIN CERTIFICATE")
echo "  $CERT_COUNT certificates in trust bundle"
echo ""
echo "Bundle status:"
oc get bundle demo-trust-bundle
