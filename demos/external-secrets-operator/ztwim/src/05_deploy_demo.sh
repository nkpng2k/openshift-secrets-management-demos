#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Deploying ClusterSecretStores and ExternalSecrets ==="

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')
echo "Vault service IP: $IP_ADDRESS"

# Expose the ESO controller's jwt-fetcher sidecar as a Service
# so namespace-scoped Webhook Generators in team namespaces can reach it
sed \
  -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
  $SCRIPT_DIR/config/jwt_server_service.yaml > $SCRIPT_DIR/config/tmp_jwt_server_service.yaml
oc apply -f $SCRIPT_DIR/config/tmp_jwt_server_service.yaml

for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  echo "--- Deploying for $NS ---"

  # Register per-team SPIFFE identity on the ESO controller pod
  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
    -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
    $SCRIPT_DIR/config/team_spiffeid.yaml > $SCRIPT_DIR/config/tmp_team_spiffeid_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_team_spiffeid_${NS}.yaml

  # ClusterSecretStore + ExternalSecret (cluster-scoped, uses ESO controller's default SPIFFE ID)
  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
    -e "s|VAULT_JWT_AUTH_PATH|$VAULT_JWT_AUTH_PATH|g" \
    -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
    $SCRIPT_DIR/config/cluster_secret_store.yaml > $SCRIPT_DIR/config/tmp_cluster_secret_store_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_cluster_secret_store_${NS}.yaml

  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    $SCRIPT_DIR/config/external_secret.yaml > $SCRIPT_DIR/config/tmp_external_secret_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_external_secret_${NS}.yaml

  # Namespace-scoped Webhook Generator pointing to ESO controller's jwt-fetcher
  # Requests the team-specific JWT (e.g., /team-a.json)
  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
    $SCRIPT_DIR/config/team_webhook_generator.yaml > $SCRIPT_DIR/config/tmp_team_webhook_generator_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_team_webhook_generator_${NS}.yaml

  # ExternalSecret to create team-jwt Secret from Webhook Generator
  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    $SCRIPT_DIR/config/team_jwt_external_secret.yaml > $SCRIPT_DIR/config/tmp_team_jwt_external_secret_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_team_jwt_external_secret_${NS}.yaml
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

  # SecretStore using team-specific JWT (namespace-scoped, per-team SPIFFE identity)
  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
    -e "s|VAULT_JWT_AUTH_PATH|$VAULT_JWT_AUTH_PATH|g" \
    $SCRIPT_DIR/config/secret_store.yaml > $SCRIPT_DIR/config/tmp_secret_store_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_secret_store_${NS}.yaml

  # ExternalSecret using namespace-scoped SecretStore
  sed \
    -e "s|TEAM_NAMESPACE|$NS|g" \
    $SCRIPT_DIR/config/external_secret_local.yaml > $SCRIPT_DIR/config/tmp_external_secret_local_${NS}.yaml
  oc apply -f $SCRIPT_DIR/config/tmp_external_secret_local_${NS}.yaml
done

echo "Waiting for all ExternalSecrets to sync..."
wait_spinner 10

for NS in $TEAM_A_NAMESPACE $TEAM_B_NAMESPACE; do
  await_all_resources_ready $NS externalsecret
done

echo "Demo deployment complete."
