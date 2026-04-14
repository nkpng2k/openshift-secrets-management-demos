#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Exec into Vault pod to add some secrets and configure vault
oc project hashicorp-vault

SA_ISSUER=$(oc get authentication.config cluster -o json | jq -r .spec.serviceAccountIssuer)
if [[ $SA_ISSUER == "" ]]; then
  oc patch authentication.config.openshift.io/cluster \
    --type=merge -p '{"spec":{"serviceAccountIssuer":"https://kubernetes.default.svc"}}'
  SA_ISSUER="https://kubernetes.default.svc"
fi

sed \
  -e "s|SA_ISSUER|$SA_ISSUER|g" \
  $SCRIPT_DIR/config/configure_vault.sh > $SCRIPT_DIR/config/tmp_configure_vault.sh

oc exec -it vault-0 -- bash -c "$(cat $SCRIPT_DIR/config/tmp_configure_vault.sh)"

oc create serviceaccount -n demo-namespace-admin eso-demo-sa

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')

sed \
  -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
  $SCRIPT_DIR/config/eso_resources.yaml > $SCRIPT_DIR/config/tmp_eso_resources.yaml
oc apply -f $SCRIPT_DIR/config/tmp_eso_resources.yaml

# Deploy demo pods to showcase events-based debugging
# - demo-app-success: mounts the ESO-managed secret correctly
# - demo-app-failure: references a non-existent secret (simulates a typo)
echo ""
echo "Deploying demo pods for events demonstration..."
oc apply -f $SCRIPT_DIR/config/demo_pods.yaml
echo "Waiting for demo-app-success pod to be ready..."
oc wait --for=condition=Ready pod/demo-app-success -n demo-namespace-user --timeout=60s
echo "demo-app-failure pod will remain in ContainerCreating (expected - secret does not exist)"
