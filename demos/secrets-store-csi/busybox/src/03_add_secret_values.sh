#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Exec into Vault pod to add some secrets and configure vault
oc project hashicorp-vault
oc patch authentication.config.openshift.io/cluster \
  --type=merge -p '{"spec":{"serviceAccountIssuer":"https://kubernetes.default.svc"}}'

oc exec -it vault-0 -- bash -c "$(cat $SCRIPT_DIR/config/configure_vault.sh)"
