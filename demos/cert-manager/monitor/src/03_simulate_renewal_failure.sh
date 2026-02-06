#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/monitor/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

oc apply -f $SCRIPT_DIR/config/broken-cert-manager.yaml

oc patch Certificate test-client-monitor -n cert-manager-monitor-ns \
  --type='merge' -p "{\"spec\":{\"issuerRef\":{\"name\":\"cm-broken-issuer\"}}}"

wait_spinner 15

oc delete secret test-client-tls-monitor

# Get OpenShift DNS name
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-ingress
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}

curl --cacert <(oc get secret -n cert-manager-monitor-ns test-client-tls-monitor -o jsonpath='{.data.ca\.crt}' | base64 -d) \
  -v https://$HOST
