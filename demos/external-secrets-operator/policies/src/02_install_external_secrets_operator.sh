#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/policies/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/variables.sh

# Create new demo project
oc new-project external-secrets-operator
oc project external-secrets-operator

# Create Operator Group and Subscription
oc apply -f $SCRIPT_DIR/config/operators.yaml

# Verify Operator
wait_spinner 5
oc get sub openshift-external-secrets-operator -n external-secrets-operator
oc get installplan -n external-secrets-operator
await_csv_ready external-secrets-operator
POD_NAME=$(get_pod_name external external-secrets-operator)
await_pod_ready $POD_NAME external-secrets-operator

# Deploy
oc apply -f $SCRIPT_DIR/config/eso.yaml

# Verify
wait_spinner 10
await_all_resources_ready external-secrets pod
