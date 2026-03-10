#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

oc apply -f $SCRIPT_DIR/config/rolebinding.yaml
