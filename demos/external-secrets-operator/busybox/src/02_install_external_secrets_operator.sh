#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/busybox/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/vault.sh
source $SCRIPT_DIR/variables.sh

# Create new demo project
oc new-project external-secrets-operator
oc project external-secrets-operator

# Create Operator Group and Subscription
oc apply -f $SCRIPT_DIR/config/operators.yaml

# Verify Operator
sleep 5
oc get sub openshift-external-secrets-operator -n external-secrets-operator
oc get installplan -n external-secrets-operator
oc get csv -n external-secrets-operator
oc get pods -n external-secrets-operator

# Deploy
oc apply -f $SCRIPT_DIR/config/eso.yaml

# Verify
sleep 5
oc get pods -n external-secrets
oc get externalsecrets.operator.openshift.io cluster \
  -n external-secrets-operator \
  -o jsonpath='{.status.conditions}' | jq .
