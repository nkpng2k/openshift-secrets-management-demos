#!/bin/bash
# Deploys the mTLS example applications:
#   - Builds a CA trust bundle ConfigMap from Root + Intermediate CA certs
#   - Deploys an nginx mTLS server
#   - Deploys a client pod for mTLS validation
#   - Runs a quick connectivity test

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/vault-pki/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

VAULT_ISSUER_NS="vault-pki-demo-ns"

# Resolve DNS for server hostname
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
DNS_HOST=mtls-server.apps.${BASE_DOMAIN}

oc project $VAULT_ISSUER_NS

# --- Build the CA trust bundle ---
# The bundle contains the intermediate CA (from the cert-manager Secret)
# and the root CA (extracted from Vault in step 02).

echo "Building CA trust bundle from Vault PKI certificate chain..."

INTERMEDIATE_CA=$(oc get secret intermediate-ca-secret -n $VAULT_ISSUER_NS -o jsonpath='{.data.tls\.crt}' | base64 -d)
ROOT_CA=$(cat $SCRIPT_DIR/config/tmp_root_ca.crt)

oc create configmap vault-pki-ca-bundle \
  --from-literal=ca-bundle.crt="$(printf '%s\n%s' "$INTERMEDIATE_CA" "$ROOT_CA")" \
  -n $VAULT_ISSUER_NS --dry-run=client -o yaml | oc apply -f -

echo "CA trust bundle ConfigMap created."

# --- Deploy the mTLS server (nginx) ---

sed \
  -e "s|VAULT_ISSUER_NS|$VAULT_ISSUER_NS|g" \
  -e "s|DNS_HOST|$DNS_HOST|g" \
  $SCRIPT_DIR/config/server_app.yaml > $SCRIPT_DIR/config/tmp_server_app.yaml

oc apply -f $SCRIPT_DIR/config/tmp_server_app.yaml

# --- Create the validation script ConfigMap ---

sed \
  -e "s|VAULT_ISSUER_NS|$VAULT_ISSUER_NS|g" \
  $SCRIPT_DIR/config/validate_mtls.sh > $SCRIPT_DIR/config/tmp_validate_mtls.sh

oc create configmap mtls-validation-script \
  --from-file=validate_mtls.sh=$SCRIPT_DIR/config/tmp_validate_mtls.sh \
  -n $VAULT_ISSUER_NS --dry-run=client -o yaml | oc apply -f -

# --- Deploy the mTLS client ---

sed \
  -e "s|VAULT_ISSUER_NS|$VAULT_ISSUER_NS|g" \
  $SCRIPT_DIR/config/client_app.yaml > $SCRIPT_DIR/config/tmp_client_app.yaml

oc apply -f $SCRIPT_DIR/config/tmp_client_app.yaml

# Wait for deployments to be ready
echo "Waiting for server and client deployments..."
wait_spinner 15

oc wait --for=condition=Available deployment/mtls-server -n $VAULT_ISSUER_NS --timeout=60s
oc wait --for=condition=Available deployment/mtls-client -n $VAULT_ISSUER_NS --timeout=60s

echo ""
echo "Deployments ready:"
oc get pods -n $VAULT_ISSUER_NS

# Quick mTLS connectivity test
echo ""
echo "Running quick mTLS connectivity test..."
CLIENT_POD=$(oc get pods -n $VAULT_ISSUER_NS -l app=mtls-client --no-headers | awk '{print $1}')
HTTP_CODE=$(oc exec $CLIENT_POD -n $VAULT_ISSUER_NS -- \
  curl -s -o /dev/null -w '%{http_code}' \
  --cert /etc/client-tls/tls.crt \
  --key /etc/client-tls/tls.key \
  --cacert /etc/trust/ca-bundle.crt \
  https://mtls-server.${VAULT_ISSUER_NS}.svc.cluster.local)

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "mTLS connectivity test PASSED (HTTP $HTTP_CODE)"
else
  echo "mTLS connectivity test FAILED (HTTP $HTTP_CODE)"
  exit 1
fi
