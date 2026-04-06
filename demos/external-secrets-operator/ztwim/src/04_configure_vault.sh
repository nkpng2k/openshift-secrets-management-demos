#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Configuring Vault JWT Auth ==="

oc project hashicorp-vault

# Determine SPIRE OIDC Discovery Provider route URL
# The OIDC DP only serves requests for its configured jwtIssuer domain (the route hostname),
# so Vault must use the external route URL, not the internal service URL.
OIDC_ROUTE_HOST=$(oc get route spire-oidc-discovery-provider -n $SPIRE_NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null)
if [[ -z "$OIDC_ROUTE_HOST" ]]; then
  echo "ERROR: Could not find OIDC Discovery Provider route in $SPIRE_NAMESPACE"
  echo "Available routes:"
  oc get route -n $SPIRE_NAMESPACE
  exit 1
fi
OIDC_DISCOVERY_URL="https://${OIDC_ROUTE_HOST}"
echo "OIDC Discovery URL: $OIDC_DISCOVERY_URL"

# Template and run Vault configuration
# The service CA bundle is mounted at /etc/pki/tls/service-ca/service-ca.crt
# via the oidc-service-ca ConfigMap (annotated for automatic CA injection)
sed \
  -e "s|VAULT_JWT_AUTH_PATH|$VAULT_JWT_AUTH_PATH|g" \
  -e "s|OIDC_DISCOVERY_URL|$OIDC_DISCOVERY_URL|g" \
  -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
  -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
  -e "s|ESO_SERVICE_ACCOUNT|$ESO_SERVICE_ACCOUNT|g" \
  -e "s|TEAM_A_NAMESPACE|$TEAM_A_NAMESPACE|g" \
  -e "s|TEAM_B_NAMESPACE|$TEAM_B_NAMESPACE|g" \
  $SCRIPT_DIR/config/configure_vault_jwt.sh > $SCRIPT_DIR/config/tmp_configure_vault.sh

oc exec -it vault-0 -n hashicorp-vault -- bash -c "$(cat $SCRIPT_DIR/config/tmp_configure_vault.sh)"

echo "Vault configuration complete."
