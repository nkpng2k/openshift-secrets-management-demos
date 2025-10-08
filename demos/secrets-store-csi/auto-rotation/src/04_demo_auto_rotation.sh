#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/auto-rotation/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Exec into Vault pod to update secret
oc project hashicorp-vault

RANDOM_NUM=$((100 + RANDOM % 1000))
NEW_PASS="demo-rotated-password-$RANDOM_NUM"
sed \
  -e "s|NEW_PASS|$NEW_PASS|g" \
  $SCRIPT_DIR/config/update_vault.sh > $SCRIPT_DIR/config/tmp_update_vault.sh

oc exec -it vault-0 -- bash -c "$(cat $SCRIPT_DIR/config/tmp_update_vault.sh)"
echo "The secret was changed to $NEW_PASS in Vault"

# Wait for 2 minutes. Default rotation polling is 2m
wait_spinner 120

# Inspect running pod to validate secret has been rotated
oc project sscsi-demo-ns

# NOTE: NO CHANGES ARE MADE TO THE DEPLOYMENT SPEC
# This code block only execs into the pod to inspect the file where the secret is stored
MOUNTED_SECRET=$(oc exec -it -n sscsi-demo-ns sscsi-demo -- cat mnt/secrets-store/db-password)
echo "The secret mounted into the pod is: $MOUNTED_SECRET"
if [[ $MOUNTED_SECRET == "$NEW_PASS" ]]; then
  echo "SUCCESS! Mounted secret is the same as the expected secret"
else
  echo "FAIL... incorrect secret"
  echo "should have been: $NEW_PASS"
fi
