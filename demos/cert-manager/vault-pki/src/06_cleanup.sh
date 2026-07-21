#!/bin/bash
# Tears down all resources created by the Vault PKI demo.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="vault-pki/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

DEMO_SRC_DIR_FULL="cert-manager/vault-pki/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR_FULL|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/vault.sh

VAULT_ISSUER_NS="vault-pki-demo-ns"

# Clean up cluster-scoped resources
oc delete clusterrolebinding vault-issuer-tokenreview-binding 2>/dev/null

# Clean up demo namespace (deletes all namespaced resources with it)
oc delete project $VAULT_ISSUER_NS

# Uninstall Vault
uninstall_vault_openshift
oc project default
oc delete project hashicorp-vault

# Clean up cert-manager operator
/bin/bash $OPERATOR_DIR/cleanup.sh

echo ""
echo "Vault PKI demo cleanup complete."
