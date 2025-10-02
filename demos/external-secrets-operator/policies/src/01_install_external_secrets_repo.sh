#!/bin/bash
# Sample script to install an `External Secrets Repository`.
# External Secrets Repository refers to a software tool like:
# CyberArk Conjur, HashiCorp Vault, or the Secret Manager for
# Any of the Cloud Service Providers.

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/policies/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $UTILS_DIR/vault.sh
source $SCRIPT_DIR/variables.sh

echo "Running helm install scripts for $EXTERNAL_SECRETS_REPO"

if [[ $EXTERNAL_SECRETS_REPO == "vault" ]]; then
  install_vault_helm_repo
else
  echo "Did not recognize repo: $EXTERNAL_SECRETS_REPO"
  exit 1
fi

echo "Installing $EXTERNAL_SECRETS_REPO on OpenShift Cluster"

if [[ $EXTERNAL_SECRETS_REPO == "vault" ]]; then
  install_vault_openshift
  await_pod_ready vault-0 hashicorp-vault
else
  echo "Did not recognize repo: $EXTERNAL_SECRETS_REPO"
  exit 1
fi
