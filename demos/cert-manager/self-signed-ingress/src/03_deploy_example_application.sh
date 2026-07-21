#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/self-signed-ingress/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Get OpenShift DNS name
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-ingress
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}
TYPE="ingress"

LEAF_DURATION="${LEAF_DURATION:-60m}"
LEAF_RENEW_BEFORE="${LEAF_RENEW_BEFORE:-10m}"

sed \
  -e "s|LEAF_DURATION|$LEAF_DURATION|g" \
  -e "s|LEAF_RENEW_BEFORE|$LEAF_RENEW_BEFORE|g" \
  -e "s|DNS_HOST|$HOST|g" \
  -e "s|TYPE|$TYPE|g" \
  $SCRIPT_DIR/config/cert_manager_example.yaml > $SCRIPT_DIR/config/tmp_cert_manager_example.yaml
oc apply -f $SCRIPT_DIR/config/tmp_cert_manager_example.yaml

# Wait a bit for the deployment to be ready
wait_spinner 15

# Run test with curl
curl --cacert <(oc get secret -n cert-manager-demo-ns test-client-tls-$TYPE -o jsonpath='{.data.ca\.crt}' | base64 -d) \
  -v https://$HOST

# Sample test without --cacert should fail
# curl -v https://$HOST
