#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/gitops/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

oc new-project eso-demo-ns
oc project eso-demo-ns

oc create serviceaccount -n eso-demo-ns eso-demo-sa

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')

sed \
  -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
  $SCRIPT_DIR/config/eso_resources.yaml > $SCRIPT_DIR/config/tmp_eso_resources.yaml
oc apply -f $SCRIPT_DIR/config/tmp_eso_resources.yaml
