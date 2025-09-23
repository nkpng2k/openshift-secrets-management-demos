#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Exec into Vault pod to add some secrets and configure vault
oc project hashicorp-vault

SA_ISSUER=$(oc get authentication.config cluster -o json | jq -r .spec.serviceAccountIssuer)
if [[ $SA_ISSUER == "" ]]; then
  oc patch authentication.config.openshift.io/cluster \
    --type=merge -p '{"spec":{"serviceAccountIssuer":"https://kubernetes.default.svc"}}'
  SA_ISSUER="https://kubernetes.default.svc"
fi

sed \
  -e "s|SA_ISSUER|$SA_ISSUER|g" \
  $SCRIPT_DIR/config/configure_vault.sh > $SCRIPT_DIR/config/tmp_configure_vault.sh

oc exec -it vault-0 -- bash -c "$(cat $SCRIPT_DIR/config/tmp_configure_vault.sh)"
