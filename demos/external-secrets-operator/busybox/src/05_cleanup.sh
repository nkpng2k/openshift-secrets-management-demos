#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/busybox/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/vault.sh

# Clean up namespace. This cleans up any resources in the namespace
oc delete project eso-demo-ns
oc project default

# Clean up cluster role bindings
oc delete clusterrolebinding eso-demo-crb

# Clean up operator group and subscription
oc delete sub openshift-external-secrets-operator -n external-secrets-operator
oc delete og openshift-external-secrets-operator -n external-secrets-operator
CSV_NAME=$(oc get csv -n external-secrets-operator --no-headers | awk '{ print $1 }')
oc delete csv -n external-secrets-operator $CSV_NAME

# Clean up operator namespaces
oc delete project external-secrets
oc delete project external-secrets-operator

# Uninstall Vault via Helm
uninstall_vault_openshift
oc project default
oc delete project hashicorp-vault
