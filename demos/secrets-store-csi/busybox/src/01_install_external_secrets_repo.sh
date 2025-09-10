#!/bin/bash

# Load in variables from varibles.sh
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/busybox/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
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
else
  echo "Did not recognize repo: $EXTERNAL_SECRETS_REPO"
  exit 1
fi
