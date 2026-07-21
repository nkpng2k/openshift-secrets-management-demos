#!/bin/bash
# Creates the demo namespace, deploys the Vault Issuer (with SA and RBAC),
# then deploys the certificate chain:
#   Vault Root CA -> Intermediate CA (on-cluster) -> Leaf certificates

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/vault-pki/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

VAULT_ISSUER_NS="vault-pki-demo-ns"

# Create demo namespace
oc new-project $VAULT_ISSUER_NS
oc project $VAULT_ISSUER_NS

# Resolve cluster DNS for certificate SANs
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
DNS_HOST=mtls-server.apps.${BASE_DOMAIN}
SVC_HOST=mtls-server.${VAULT_ISSUER_NS}.svc.cluster.local

# --- Deploy the Vault Issuer (SA, token Secret, RBAC, Issuer) ---

sed \
  -e "s|VAULT_ISSUER_NS|$VAULT_ISSUER_NS|g" \
  $SCRIPT_DIR/config/vault_issuer.yaml > $SCRIPT_DIR/config/tmp_vault_issuer.yaml

oc apply -f $SCRIPT_DIR/config/tmp_vault_issuer.yaml

# Wait for the SA token to be populated by the token controller
echo "Waiting for ServiceAccount token..."
wait_spinner 10

TOKEN=$(oc get secret vault-issuer-token -n $VAULT_ISSUER_NS -o jsonpath='{.data.token}' 2>/dev/null)
TIMEOUT=30
ELAPSED=0
while [[ -z "$TOKEN" && $ELAPSED -lt $TIMEOUT ]]; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  TOKEN=$(oc get secret vault-issuer-token -n $VAULT_ISSUER_NS -o jsonpath='{.data.token}' 2>/dev/null)
done

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: vault-issuer-token Secret does not have a token."
  oc describe secret vault-issuer-token -n $VAULT_ISSUER_NS
  exit 1
fi
echo "ServiceAccount token is ready."

# Wait for the Vault Issuer to become ready
echo "Waiting for Vault Issuer to become ready..."
READY=$(oc get issuer vault-pki-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
TIMEOUT=60
ELAPSED=0
while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  READY=$(oc get issuer vault-pki-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
done

if [[ "$READY" == "True" ]]; then
  echo "Vault Issuer (sign-intermediate) is ready."
else
  echo "ERROR: Vault Issuer is not ready after ${TIMEOUT}s."
  oc describe issuer vault-pki-issuer -n $VAULT_ISSUER_NS
  exit 1
fi

# Wait for the Vault Leaf Issuer to become ready
echo "Waiting for Vault Leaf Issuer to become ready..."
READY=$(oc get issuer vault-pki-leaf-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
TIMEOUT=60
ELAPSED=0
while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  READY=$(oc get issuer vault-pki-leaf-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
done

if [[ "$READY" == "True" ]]; then
  echo "Vault Issuer (direct leaf) is ready."
else
  echo "ERROR: Vault Leaf Issuer is not ready after ${TIMEOUT}s."
  oc describe issuer vault-pki-leaf-issuer -n $VAULT_ISSUER_NS
  exit 1
fi

# --- Deploy the certificate chain ---

sed \
  -e "s|VAULT_ISSUER_NS|$VAULT_ISSUER_NS|g" \
  -e "s|DNS_HOST|$DNS_HOST|g" \
  -e "s|SVC_HOST|$SVC_HOST|g" \
  $SCRIPT_DIR/config/certificates.yaml > $SCRIPT_DIR/config/tmp_certificates.yaml

oc apply -f $SCRIPT_DIR/config/tmp_certificates.yaml

# Wait for intermediate CA certificate (issued by Vault)
echo ""
echo "Waiting for Intermediate CA certificate (issued by Vault)..."
READY=$(oc get certificate intermediate-ca -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
TIMEOUT=120
ELAPSED=0
while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  READY=$(oc get certificate intermediate-ca -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
done

if [[ "$READY" == "True" ]]; then
  echo "  intermediate-ca: Ready"
else
  echo "  intermediate-ca: NOT Ready (timed out after ${TIMEOUT}s)"
  oc describe certificate intermediate-ca -n $VAULT_ISSUER_NS
  exit 1
fi

# Wait for the intermediate CA Issuer to become ready
echo "Waiting for Intermediate CA Issuer..."
READY=$(oc get issuer intermediate-ca-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
TIMEOUT=60
ELAPSED=0
while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  READY=$(oc get issuer intermediate-ca-issuer -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
done

if [[ "$READY" == "True" ]]; then
  echo "  intermediate-ca-issuer: Ready"
else
  echo "  intermediate-ca-issuer: NOT Ready (timed out after ${TIMEOUT}s)"
  oc describe issuer intermediate-ca-issuer -n $VAULT_ISSUER_NS
  exit 1
fi

# Wait for leaf certificates (issued by local intermediate CA)
echo ""
echo "Waiting for leaf certificates..."

CERT_NAMES=("server-cert" "client-cert" "vault-direct-leaf-cert")
for CERT in "${CERT_NAMES[@]}"; do
  echo "Checking certificate: $CERT"
  READY=$(oc get certificate $CERT -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  TIMEOUT=60
  ELAPSED=0
  while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    READY=$(oc get certificate $CERT -n $VAULT_ISSUER_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  done
  if [[ "$READY" == "True" ]]; then
    echo "  $CERT: Ready"
  else
    echo "  $CERT: NOT Ready (timed out after ${TIMEOUT}s)"
    oc describe certificate $CERT -n $VAULT_ISSUER_NS
    exit 1
  fi
done

echo ""
echo "All certificates issued successfully:"
echo ""
echo "Certificate chain:"
echo "  Vault Root CA -> Intermediate CA (cert-manager) -> Leaf Certs"
echo ""
oc get certificate -n $VAULT_ISSUER_NS
echo ""
oc get issuer -n $VAULT_ISSUER_NS
