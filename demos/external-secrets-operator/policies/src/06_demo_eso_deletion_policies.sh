#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/policies/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Exec into Vault pod to delete the secret
oc exec \
  -it vault-0 \
  -n hashicorp-vault \
  -- bash -c "$(cat $SCRIPT_DIR/config/delete_kv_vault.sh)"

# Wait for 1 minute. Configured refreshPolicy
wait_spinner 60

# Validate that secret is deleted
# Step 1: check events includes Deleted
oc events --for externalsecret/vault-external-secret -n eso-demo-ns
SECRET=$(oc get secret | grep vault-secret-example)
if [[ $SECRET == "" ]]; then
  echo "SUCCESS! Secret no longer exists. Deleted due to deletionPolicy"
else
  echo "FAIL... no secret should exist"
fi
