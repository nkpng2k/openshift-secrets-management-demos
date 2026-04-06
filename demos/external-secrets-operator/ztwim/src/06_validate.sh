#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Validating ZTWIM + ESO Demo ==="

PASS=true

# Check JWT Secret exists
echo ""
echo "--- SPIFFE JWT Secret ---"
if oc get secret spiffe-jwt -n $ESO_NAMESPACE &>/dev/null; then
  echo "spiffe-jwt Secret: exists"
else
  echo "ERROR: spiffe-jwt Secret not found in $ESO_NAMESPACE"
  PASS=false
fi

# Check ClusterSecretStores
echo ""
echo "--- ClusterSecretStores ---"
for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  CSS_STATUS=$(oc get clustersecretstore vault-$NS -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  CSS_TYPE=$(oc get clustersecretstore vault-$NS -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
  echo "vault-$NS: $CSS_TYPE = $CSS_STATUS"
  if [[ "$CSS_STATUS" != "True" ]]; then
    echo "WARNING: ClusterSecretStore vault-$NS not ready"
    PASS=false
  fi
done

# Check ExternalSecrets and team secrets (ClusterSecretStore)
for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  echo ""
  echo "--- Namespace: $NS (ClusterSecretStore) ---"

  ES_STATUS=$(oc get externalsecret team-credentials -n $NS -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  ES_REASON=$(oc get externalsecret team-credentials -n $NS -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
  echo "ExternalSecret: $ES_REASON = $ES_STATUS"
  if [[ "$ES_STATUS" != "True" ]]; then
    echo "WARNING: ExternalSecret team-credentials not synced in $NS"
    PASS=false
  fi

  USERNAME=$(oc get secret team-secret -n $NS -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
  PASSWORD=$(oc get secret team-secret -n $NS -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
  echo "Synced secret: username=$USERNAME password=$PASSWORD"
done

# Check SecretStores (namespace-scoped)
echo ""
echo "--- SecretStores (namespace-scoped) ---"
for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  SS_STATUS=$(oc get secretstore vault-local -n $NS -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  SS_TYPE=$(oc get secretstore vault-local -n $NS -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
  echo "vault-local ($NS): $SS_TYPE = $SS_STATUS"
  if [[ "$SS_STATUS" != "True" ]]; then
    echo "WARNING: SecretStore vault-local not ready in $NS"
    PASS=false
  fi
done

# Check ExternalSecrets and team secrets (SecretStore)
for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  echo ""
  echo "--- Namespace: $NS (SecretStore) ---"

  ES_STATUS=$(oc get externalsecret team-credentials-local -n $NS -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  ES_REASON=$(oc get externalsecret team-credentials-local -n $NS -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
  echo "ExternalSecret: $ES_REASON = $ES_STATUS"
  if [[ "$ES_STATUS" != "True" ]]; then
    echo "WARNING: ExternalSecret team-credentials-local not synced in $NS"
    PASS=false
  fi

  USERNAME=$(oc get secret team-secret-local -n $NS -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
  PASSWORD=$(oc get secret team-secret-local -n $NS -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
  echo "Synced secret: username=$USERNAME password=$PASSWORD"
done

echo ""
echo "=== Identity Isolation Check ==="
TEAM_A_PWD=$(oc get secret team-secret -n $TEAM_A_NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
TEAM_B_PWD=$(oc get secret team-secret -n $TEAM_B_NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
TEAM_A_LOCAL_PWD=$(oc get secret team-secret-local -n $TEAM_A_NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
TEAM_B_LOCAL_PWD=$(oc get secret team-secret-local -n $TEAM_B_NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [[ "$TEAM_A_PWD" != "$TEAM_B_PWD" ]] && [[ -n "$TEAM_A_PWD" ]] && [[ -n "$TEAM_B_PWD" ]]; then
  echo "SUCCESS: ClusterSecretStore - teams have different secrets."
else
  echo "FAIL: ClusterSecretStore - expected different secrets for each team."
  PASS=false
fi

if [[ "$TEAM_A_LOCAL_PWD" != "$TEAM_B_LOCAL_PWD" ]] && [[ -n "$TEAM_A_LOCAL_PWD" ]] && [[ -n "$TEAM_B_LOCAL_PWD" ]]; then
  echo "SUCCESS: SecretStore - teams have different secrets."
else
  echo "FAIL: SecretStore - expected different secrets for each team."
  PASS=false
fi

if [[ "$TEAM_A_PWD" == "$TEAM_A_LOCAL_PWD" ]] && [[ "$TEAM_B_PWD" == "$TEAM_B_LOCAL_PWD" ]]; then
  echo "SUCCESS: ClusterSecretStore and SecretStore secrets match for each team."
else
  echo "FAIL: ClusterSecretStore and SecretStore secrets differ for the same team."
  PASS=false
fi

echo ""
if [[ "$PASS" == true ]]; then
  echo "=== ALL VALIDATIONS PASSED ==="
else
  echo "=== SOME VALIDATIONS FAILED ==="
  echo "Troubleshooting:"
  echo "  jwt-fetcher logs:   oc logs -n $ESO_NAMESPACE deploy/external-secrets -c jwt-fetcher"
  echo "  ESO controller:     oc logs -n $ESO_NAMESPACE deploy/external-secrets -c external-secrets"
  exit 1
fi
