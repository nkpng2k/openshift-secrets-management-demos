#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="trust-manager/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

CA_NS="cert-manager"

# Clean up cluster-scoped resources
oc delete bundle demo-trust-bundle 2>/dev/null
oc delete clusterissuer intermediate-ca-cluster-issuer 2>/dev/null
oc delete trustmanager cluster 2>/dev/null

# Clean up CA resources from cert-manager namespace
oc delete certificate root-ca intermediate-ca -n $CA_NS 2>/dev/null
oc delete issuer selfsigned-issuer root-ca-issuer -n $CA_NS 2>/dev/null
oc delete secret root-ca-secret intermediate-ca-secret -n $CA_NS 2>/dev/null

# Clean up workload namespaces
oc delete project trust-manager-server-ns
oc delete project trust-manager-client-ns
oc project default

# Clean up operator
/bin/bash $OPERATOR_DIR/cleanup.sh

echo ""
echo "NOTE: The TechPreviewNoUpgrade FeatureGate cannot be reverted."
echo "      This setting is permanent for the lifetime of the cluster."
