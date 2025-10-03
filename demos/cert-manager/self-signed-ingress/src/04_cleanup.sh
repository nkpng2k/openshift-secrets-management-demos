#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="self-signed-ingress/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Clean up demo namespace. This cleans up any resources in the namespace
oc delete project cert-manager-demo-ns
oc project default

# Clean up operator
/bin/bash $OPERATOR_DIR/cleanup.sh
