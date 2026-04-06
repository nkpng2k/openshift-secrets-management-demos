#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $UTILS_DIR/vault.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Installing ZTWIM Operator ==="
oc apply -f $SCRIPT_DIR/config/ztwim_operator.yaml
echo "Waiting for ZTWIM operator CSV to succeed..."
wait_spinner 15
oc wait --all=true --for=jsonpath='{.status.phase}'=Succeeded csv -n zero-trust-workload-identity-manager --timeout=300s

echo "=== Installing Vault (dev mode) ==="
install_vault_helm_repo

# Create Vault namespace and inject the OpenShift service CA ConfigMap
# before Helm install so it can be mounted into the Vault pod
oc new-project hashicorp-vault
oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: oidc-service-ca
  namespace: hashicorp-vault
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF

install_vault_openshift
await_all_resources_ready hashicorp-vault pod

echo "=== Creating Team Namespaces ==="
oc new-project $TEAM_A_NAMESPACE
oc new-project $TEAM_B_NAMESPACE

echo "Install complete."
