#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/auto-rotation/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/vault.sh
source $SCRIPT_DIR/variables.sh

# Create Operator Group and Subscription
oc apply -f $SCRIPT_DIR/config/operators.yaml

# Verify
sleep 5
oc get sub secrets-store-csi-driver-operator -n openshift-cluster-csi-drivers
oc get installplan -n openshift-cluster-csi-drivers
oc get csv -n openshift-cluster-csi-drivers

# Deploy
oc apply -f $SCRIPT_DIR/config/sscsi.yaml
