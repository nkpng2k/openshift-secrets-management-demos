#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/operator"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Create Operator Group and Subscription
oc apply -f $SCRIPT_DIR/config/operator.yaml

# Verify
wait_spinner 5
oc get sub secrets-store-csi-driver-operator -n openshift-cluster-csi-drivers
oc get installplan -n openshift-cluster-csi-drivers
await_csv_ready openshift-cluster-csi-drivers
POD_NAME=$(get_pod_name secrets openshift-cluster-csi-drivers)
await_pod_ready $POD_NAME openshift-cluster-csi-drivers

# Deploy
oc apply -f $SCRIPT_DIR/config/sscsi.yaml

# Wait for SSCSI Driver to complete install
# NOTE: Throws exception if this step isn't completed
while [[ $(oc get CSIDriver -n openshift-cluster-csi-drivers | grep "secrets-store") == "" ]]; do
  echo "Waiting for SSCSI driver install"
  sleep 10
done
