#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/gitops/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

oc project openshift-gitops

oc create serviceaccount -n openshift-gitops eso-demo-sa

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')

# Simple input for necessary information
echo "Enter GitHub App ID (1234567): "
read GH_APP_ID

echo "Enter GitHub Install ID (123456789): "
read GH_INSTALL_ID

echo "Enter GitHub Repo (https://github.com/project/repository): "
read GH_REPO

sed \
  -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
  -e "s|GH_APP_ID|$GH_APP_ID|g" \
  -e "s|GH_INSTALL_ID|$GH_INSTALL_ID|g" \
  -e "s|GH_REPO|$GH_REPO|g" \
  $SCRIPT_DIR/config/eso_resources.yaml > $SCRIPT_DIR/config/tmp_eso_resources.yaml
oc apply -f $SCRIPT_DIR/config/tmp_eso_resources.yaml
