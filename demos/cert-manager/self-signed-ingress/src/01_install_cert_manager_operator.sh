#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/self-signed-ingress/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Create new demo project
oc new-project cert-manager-operator
oc project cert-manager-operator

# Create Operator Group and Subscription
oc apply -f $SCRIPT_DIR/config/operators.yaml

# Verify Operator
wait_spinner 5
await_csv_ready cert-manager-operator
POD_NAME=$(get_pod_name cert cert-manager-operator)
await_pod_ready $POD_NAME cert-manager-operator
