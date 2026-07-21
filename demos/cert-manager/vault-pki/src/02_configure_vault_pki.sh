#!/bin/bash
# Configures Vault with a Root CA PKI engine and Kubernetes auth
# so that cert-manager can authenticate and request certificates.
#
# After configuration, extracts the Root CA certificate for later
# use in the CA trust bundle.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/vault-pki/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

VAULT_NS="hashicorp-vault"
VAULT_ISSUER_NS="vault-pki-demo-ns"
CERT_MANAGER_SA="vault-issuer-sa"

oc project $VAULT_NS

# Get the ServiceAccount issuer for Kubernetes auth configuration
SA_ISSUER=$(oc get authentication.config cluster -o json | jq -r .spec.serviceAccountIssuer)
if [[ $SA_ISSUER == "" ]]; then
  oc patch authentication.config.openshift.io/cluster \
    --type=merge -p '{"spec":{"serviceAccountIssuer":"https://kubernetes.default.svc"}}'
  SA_ISSUER="https://kubernetes.default.svc"
fi

echo "Configuring Vault PKI..."
echo "  SA Issuer:       $SA_ISSUER"
echo "  Issuer SA:       $CERT_MANAGER_SA"
echo "  Issuer NS:       $VAULT_ISSUER_NS"

# Substitute placeholders and run inside the Vault pod
sed \
  -e "s|SA_ISSUER|$SA_ISSUER|g" \
  -e "s|CERT_MANAGER_SA|$CERT_MANAGER_SA|g" \
  -e "s|VAULT_ISSUER_NS|$VAULT_ISSUER_NS|g" \
  $SCRIPT_DIR/config/configure_vault_pki.sh > $SCRIPT_DIR/config/tmp_configure_vault_pki.sh

oc exec vault-0 -- bash -c "$(cat $SCRIPT_DIR/config/tmp_configure_vault_pki.sh)"

# Extract the Root CA certificate from Vault for trust bundle creation
echo ""
echo "Extracting Root CA certificate from Vault..."
oc exec vault-0 -n $VAULT_NS -- cat /tmp/root_ca.crt > $SCRIPT_DIR/config/tmp_root_ca.crt

echo "Root CA certificate saved."
echo ""
echo "Vault PKI configuration complete."
echo "  Root CA:         Vault PKI Demo Root CA"
echo "  Sign Path:       pki/root/sign-intermediate"
echo "  K8s Auth Role:   cert-manager-role"
echo "  Policy:          cert-manager-pki"
