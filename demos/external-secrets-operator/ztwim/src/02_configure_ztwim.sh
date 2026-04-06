#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Configuring ZTWIM ==="

# Determine cluster apps domain for OIDC issuer
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Apps domain: $APPS_DOMAIN"

# Apply ZeroTrustWorkloadIdentityManager CR and SPIRE operand CRs
sed \
  -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
  -e "s|APPS_DOMAIN|$APPS_DOMAIN|g" \
  $SCRIPT_DIR/config/ztwim_config.yaml > $SCRIPT_DIR/config/tmp_ztwim_config.yaml
oc apply -f $SCRIPT_DIR/config/tmp_ztwim_config.yaml

echo "Waiting for SPIRE components to start..."
wait_spinner 30

echo "Waiting for all SPIRE pods to be ready..."
await_all_resources_ready $SPIRE_NAMESPACE pod

echo "ZTWIM configuration complete."
