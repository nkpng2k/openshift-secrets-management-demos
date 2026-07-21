#!/bin/bash
# Installs HashiCorp Vault (dev mode) and the cert-manager operator on OpenShift.
# Vault is installed first so it is ready by the time cert-manager needs it.
# WARNING: Vault dev mode is NOT recommended for production environments.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/vault-pki/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $UTILS_DIR/vault.sh
source $SCRIPT_DIR/config/variables.sh

DEMO_SRC_DIR="vault-pki/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# --- Install Vault ---

echo "Adding HashiCorp Helm repository..."
install_vault_helm_repo

echo "Installing Vault on OpenShift cluster..."
install_vault_openshift

echo "Waiting for Vault pod to be ready..."
await_pod_ready vault-0 hashicorp-vault

echo ""
echo "Vault is running in dev mode."
echo "  Namespace: hashicorp-vault"
echo "  Pod: vault-0"
echo ""

# --- Install cert-manager operator ---

echo "Installing cert-manager operator..."
/bin/bash $OPERATOR_DIR/install.sh
