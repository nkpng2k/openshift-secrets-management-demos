#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

oc project cert-manager-monitor-ns

oc apply -f $SCRIPT_DIR/config/rules.yaml
