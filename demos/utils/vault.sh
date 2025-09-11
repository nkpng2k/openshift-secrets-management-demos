#!/bin/bash
# A simple utility script to install the Community version of HashiCorp Vault
# so that the demos can ensure a functioning external secrets repository
# to use during their runtime.
# WARNING: this is NOT recommended for production environments.

install_vault_helm_repo() {
  helm repo add $HASHICORP_HELM_REPO $HASHICORP_HELM_REPO_URL
  helm repo update
}

install_vault_openshift() {
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
}

patch_daemonset_csi() {
  # Patch daemonset due to bug in Vault CSI Manifest
  oc patch daemonset vault-csi-provider --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"privileged": true} }]'
}

uninstall_vault_openshift() {
  oc project hashicorp-vault
  helm uninstall vault
}
