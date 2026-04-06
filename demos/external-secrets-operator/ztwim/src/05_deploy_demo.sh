#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Deploying ClusterSecretStores and ExternalSecrets ==="

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')
echo "Vault service IP: $IP_ADDRESS"

for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  echo "--- Deploying team resources for $NS ---"

  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
    -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
    -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
    -e "s|VAULT_JWT_AUTH_PATH|$VAULT_JWT_AUTH_PATH|g" \
    $SCRIPT_DIR/config/team_resources.yaml > $SCRIPT_DIR/config/tmp_team_resources_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_team_resources_${NS}.yaml
done

echo "Waiting for per-team SPIFFE identities to propagate..."
wait_spinner 15

echo "Waiting for team-jwt Secrets..."
for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  RETRIES=0
  MAX_RETRIES=60
  while ! oc get secret team-jwt -n $NS &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
      echo "ERROR: Timed out waiting for team-jwt Secret in $NS"
      echo "Check jwt-fetcher logs: oc logs -n $ESO_NAMESPACE deploy/external-secrets -c jwt-fetcher"
      exit 1
    fi
    sleep 5
  done
  echo "team-jwt Secret created in $NS"
done

for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  echo "--- Deploying SecretStore for $NS ---"

  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
    -e "s|VAULT_JWT_AUTH_PATH|$VAULT_JWT_AUTH_PATH|g" \
    $SCRIPT_DIR/config/team_store_resources.yaml > $SCRIPT_DIR/config/tmp_team_store_resources_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_team_store_resources_${NS}.yaml
done

echo "Waiting for all ExternalSecrets to sync..."
wait_spinner 10

for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  await_all_resources_ready $NS externalsecret
done

echo "Demo deployment complete."
