#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/busybox/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/vault.sh

# Clean up namespace. This cleans up any resources in the namespace
oc delete project sscsi-demo-ns
oc project default

# Clean up operator group and subscription
oc delete ClusterCSIDriver secrets-store.csi.k8s.io
oc delete sub secrets-store-csi-driver-operator -n openshift-cluster-csi-drivers
oc delete og secrets-store-csi-driver-og -n openshift-cluster-csi-drivers
CSV_NAME=$(oc get csv -n openshift-cluster-csi-drivers --no-headers | awk '{ print $1 }')
oc delete csv -n openshift-cluster-csi-drivers $CSV_NAME

# Uninstall Vault via Helm
uninstall_vault_openshift
