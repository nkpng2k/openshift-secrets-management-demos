#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="gitops/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")
UTILS_DIR=$(sed "s|external-secrets-operator/$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

oc new-project eso-argo-demo-ns
oc project eso-argo-demo-ns
oc label namespace eso-argo-demo-ns "argocd.argoproj.io/managed-by=openshift-gitops"

# Simple input for necessary information
echo "Enter GitHub Repo: "
read GH_REPO

echo "Enter application directory path: "
read GH_PATH

echo "Enter branch name: "
read GH_BRANCH

sed \
  -e "s|GH_PATH|$GH_PATH|g" \
  -e "s|GH_BRANCH|$GH_BRANCH|g" \
  -e "s|GH_REPO|$GH_REPO|g" \
  $SCRIPT_DIR/config/argocd_resources.yaml > $SCRIPT_DIR/config/tmp_argocd_resources.yaml


oc apply -f $SCRIPT_DIR/config/tmp_argocd_resources.yaml

wait_spinner 60
await_all_resources_ready eso-argo-demo-ns pod
