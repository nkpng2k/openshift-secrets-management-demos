#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="trust-manager/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Run generalized install scripts
/bin/bash $OPERATOR_DIR/install.sh

# Check if cert-manager 1.19+ requires TechPreviewNoUpgrade FeatureGate
CM_VERSION=$(oc get csv -n cert-manager-operator --no-headers 2>/dev/null | awk '{print $1}' | grep -oE '[0-9]+\.[0-9]+')
if [[ "$CM_VERSION" == "1.19" ]]; then
  if ! oc get featuregate cluster -o yaml 2>/dev/null | grep -q "TechPreviewNoUpgrade"; then
    echo ""
    echo "ERROR: cert-manager $CM_VERSION requires TechPreviewNoUpgrade FeatureGate for trust-manager."
    echo ""
    echo "Enable it with:"
    echo "  oc patch featuregate/cluster --type=merge -p '{\"spec\":{\"featureSet\":\"TechPreviewNoUpgrade\"}}'"
    echo ""
    echo "WARNING: This is an irreversible change. Wait for the rolling node update to"
    echo "         complete before re-running this script."
    exit 1
  fi
  echo "TechPreviewNoUpgrade FeatureGate is enabled."
fi
