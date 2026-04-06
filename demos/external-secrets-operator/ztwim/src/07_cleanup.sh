#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/vault.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Cleaning Up ZTWIM + ESO Demo ==="

# Delete team namespaces
echo "Deleting team namespaces..."
oc delete project $TEAM_A_NAMESPACE --ignore-not-found
oc delete project $TEAM_B_NAMESPACE --ignore-not-found

# Delete cluster-scoped resources
echo "Deleting ClusterSecretStores..."
oc delete clustersecretstore vault-$TEAM_A_NAMESPACE vault-$TEAM_B_NAMESPACE --ignore-not-found

echo "Deleting Webhook Generator..."
oc delete webhook spiffe-jwt-generator -n $ESO_NAMESPACE --ignore-not-found

echo "Deleting ClusterSPIFFEIDs..."
oc delete clusterspiffeid eso-controller eso-$TEAM_A_NAMESPACE eso-$TEAM_B_NAMESPACE --ignore-not-found

# Uninstall ESO
echo "Uninstalling ESO..."
helm uninstall external-secrets -n $ESO_NAMESPACE
oc delete project $ESO_NAMESPACE --ignore-not-found

# Uninstall Vault
echo "Uninstalling Vault..."
uninstall_vault_openshift
oc project default
oc delete project hashicorp-vault --ignore-not-found

# Clean up tmp files
rm -f $SCRIPT_DIR/config/tmp_*

echo "Cleanup complete."
