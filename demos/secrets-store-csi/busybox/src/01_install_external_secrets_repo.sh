#!/bin/bash

# Load in variables from varibles.sh
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/variables.sh

echo "Running helm install scripts for $EXTERNAL_SECRETS_REPO"

if [[ $EXTERNAL_SECRETS_REPO == "vault" ]]; then
  helm repo add $HASHICORP_HELM_REPO $HASHICORP_HELM_REPO_URL
  helm repo update
else
  echo "Did not recognize repo: $EXTERNAL_SECRETS_REPO"
  exit 1
fi

echo "Installing $EXTERNAL_SECRETS_REPO on OpenShift Cluster"

if [[ $EXTERNAL_SECRETS_REPO == "vault" ]]; then
  # NOTE: Must have `oc`` installed and logged in with admin privileges
  oc new-project hashicorp-vault
  oc project hashicorp-vault
  oc adm policy add-scc-to-user privileged \
    system:serviceaccount:hashicorp-vault:vault-csi-provider

  sed \
    -e "s|VAULT_IMAGE_REPO|$VAULT_IMAGE_REPO|g" \
    -e "s|VAULT_IMAGE_TAG|$VAULT_IMAGE_TAG|g" \
    $SCRIPT_DIR/config/vault_values.yaml > $SCRIPT_DIR/config/tmp_vault_values.yaml

  helm install \
    -n hashicorp-vault vault hashicorp/vault \
    --values $SCRIPT_DIR/config/tmp_vault_values.yaml

  oc patch daemonset vault-csi-provider --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"privileged": true} }]'
else
  echo "Did not recognize repo: $EXTERNAL_SECRETS_REPO"
  exit 1
fi
