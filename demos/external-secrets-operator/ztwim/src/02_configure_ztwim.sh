#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Configuring ZTWIM ==="

# Apply ZeroTrustWorkloadIdentityManager CR
sed \
  -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
  $SCRIPT_DIR/config/ztwim_instance.yaml > $SCRIPT_DIR/config/tmp_ztwim_instance.yaml
oc apply -f $SCRIPT_DIR/config/tmp_ztwim_instance.yaml

# Determine cluster apps domain for OIDC issuer
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Apps domain: $APPS_DOMAIN"

# Apply operand CRs (SpireServer, SpireAgent, SpiffeCSIDriver, SpireOIDCDiscoveryProvider)
echo "Creating SPIRE operand CRs..."
sed \
  -e "s|APPS_DOMAIN|$APPS_DOMAIN|g" \
  $SCRIPT_DIR/config/ztwim_operands.yaml > $SCRIPT_DIR/config/tmp_ztwim_operands.yaml
oc apply -f $SCRIPT_DIR/config/tmp_ztwim_operands.yaml

echo "Waiting for SPIRE components to start..."
wait_spinner 30

echo "Waiting for all SPIRE pods to be ready..."
await_all_resources_ready $SPIRE_NAMESPACE pod

echo "=== Creating ClusterSPIFFEID for ESO controller ==="
sed \
  -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
  -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
  $SCRIPT_DIR/config/cluster_spiffeid.yaml > $SCRIPT_DIR/config/tmp_cluster_spiffeid.yaml
oc apply -f $SCRIPT_DIR/config/tmp_cluster_spiffeid.yaml

echo "ZTWIM configuration complete."
