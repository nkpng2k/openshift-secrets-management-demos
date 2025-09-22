#!/bin/bash

# Clean up demo namespace. This cleans up any resources in the namespace
oc delete project cert-manager-demo-ns
oc project default

# Clean up operator group and subscription
oc delete sub openshift-cert-manager-operator -n cert-manager-operator
oc delete og openshift-cert-manager-operator -n cert-manager-operator
CSV_NAME=$(oc get csv -n cert-manager-operator --no-headers | awk '{ print $1 }')
oc delete csv -n cert-manager-operator $CSV_NAME

# Clean up operator namespaces
oc delete project cert-manager-operator
oc delete project cert-manager
