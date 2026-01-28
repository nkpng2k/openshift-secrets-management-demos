#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/operator"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

# Create new demo project
oc new-project external-secrets-operator
oc project external-secrets-operator

# Create Operator Group and Subscription
oc apply -f $SCRIPT_DIR/config/operator.yaml

# Verify Operator
wait_spinner 5
oc wait --all=true --for=jsonpath='{.status.phase}'=Succeeded csv
await_all_resources_ready external-secrets-operator pod

# Deploy
oc apply -f $SCRIPT_DIR/config/eso.yaml

# Verify
wait_spinner 10
await_all_resources_ready external-secrets pod
