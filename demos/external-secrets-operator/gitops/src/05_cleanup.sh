#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="gitops/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Clean up demo namespace
oc delete project eso-argo-demo-ns

# Clean up RBAC permissions
oc delete serviceaccount -n openshift-gitops eso-demo-sa

# Clean up ArgoCD operator 
oc delete sub openshift-gitops-operator -n openshift-gitops-operator
oc delete og openshift-gitops-operator -n openshift-gitops-operator
CSV_NAME=$(oc get csv -n openshift-gitops-operator --no-headers | awk '{ print $1 }')
oc delete csv -n openshift-gitops-operator $CSV_NAME

oc delete project openshift-gitops

# Clean up operator
/bin/bash $OPERATOR_DIR/cleanup.sh
/bin/bash $OPERATOR_DIR/cleanup_vault.sh
