#!/bin/bash

# source util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="gitops/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")
UTILS_DIR=$(sed "s|external-secrets-operator/$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Run generalized install scripts
/bin/bash $OPERATOR_DIR/install_vault.sh
/bin/bash $OPERATOR_DIR/install.sh

# Install ArgoCD (GitOps)
oc create ns openshift-gitops-operator
oc apply -f $SCRIPT_DIR/config/gitops.yaml
oc wait --all=true --for=jsonpath='{.status.phase}'=Succeeded csv

wait_spinner 10
await_all_resources_ready openshift-gitops-operator pod
