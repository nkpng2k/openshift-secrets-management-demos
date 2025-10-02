#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/policies/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Exec into Vault pod to update the secret
oc project hashicorp-vault

RANDOM_NUM=$((100 + RANDOM % 1000))
NEW_PASS="demo-rotated-password-$RANDOM_NUM"
sed \
  -e "s|NEW_PASS|$NEW_PASS|g" \
  $SCRIPT_DIR/config/update_vault.sh > $SCRIPT_DIR/config/tmp_update_vault.sh

oc exec -it vault-0 -- bash -c "$(cat $SCRIPT_DIR/config/tmp_update_vault.sh)"
echo "The secret was changed to $NEW_PASS in Vault"

# Wait for 1 minute. Configured refreshInterval
wait_spinner 60

# Inspect running deployment to validate secret has changed
oc project eso-demo-ns

ENV_SECRET=$(oc exec -it -n eso-demo-ns eso-demo -- env | grep DEMO_PWD)
MOUNTED_SECRET=$(oc exec -it -n eso-demo-ns eso-demo -- cat /mnt/demo-vol/password)
echo "The secret mounted into the pod is: $MOUNTED_SECRET"
echo "The secret env var in the pod is: $ENV_SECRET"

if [[ $MOUNTED_SECRET == "$NEW_PASS" ]]; then
  echo "SUCCESS! Mounted secret is the same as the expected secret"
else
  echo "FAIL... incorrect secret"
  echo "should have been: $NEW_PASS"
fi
