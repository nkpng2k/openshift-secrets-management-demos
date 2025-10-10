#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secrets-store-csi/busybox/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

oc new-project sscsi-demo-ns
oc project sscsi-demo-ns

oc create serviceaccount -n sscsi-demo-ns sscsi-demo-sa

oc apply -f $SCRIPT_DIR/config/sscsi_resources.yaml

# Wait a bit and then validate secret is mounted
wait_spinner 5
await_pod_ready sscsi-demo sscsi-demo-ns
MOUNTED_SECRET=$(oc exec -it -n sscsi-demo-ns sscsi-demo -- cat mnt/secrets-store/db-password)
echo "The secret mounted into the pod is: $MOUNTED_SECRET"
if [[ $MOUNTED_SECRET == "demo-secret-password-123" ]]; then
  echo "SUCCESS! Mounted secret is the same as the expected secret"
else
  echo "FAIL... incorrect secret"
  echo "should have been: demo-secret-password-123"
fi
