#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="trust-manager/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Clean up trust-manager Bundle and TrustManager CR (cluster-scoped resources)
oc delete bundle demo-trust-bundle 2>/dev/null
oc delete trustmanager cluster 2>/dev/null

# Clean up demo namespaces
oc delete project trust-manager-demo-ns
oc delete project trust-manager-consumer-ns
oc project default

# Clean up operator
/bin/bash $OPERATOR_DIR/cleanup.sh

echo ""
echo "NOTE: The TechPreviewNoUpgrade FeatureGate cannot be reverted."
echo "      This setting is permanent for the lifetime of the cluster."
