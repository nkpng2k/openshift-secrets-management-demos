#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create new demo project
oc new-project cert-manager-demo-ns
oc project cert-manager-demo-ns

# Deploy cert-manager Issuer and Certificates
oc apply -f $SCRIPT_DIR/config/cert_manager_crds.yaml
