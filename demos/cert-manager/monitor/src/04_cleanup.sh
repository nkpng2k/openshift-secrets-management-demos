#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="self-signed-ingress/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

oc delete project cert-manager-monitor-ns
oc project default

# Cleanup operator
/bin/bash $OPERATOR_DIR/cleanup.sh
