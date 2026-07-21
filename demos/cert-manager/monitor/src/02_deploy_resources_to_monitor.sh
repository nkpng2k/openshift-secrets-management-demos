#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/monitor/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Create new demo project
oc new-project cert-manager-monitor-ns
oc project cert-manager-monitor-ns

# Deploy Prometheus monitoring rules
oc apply -f $SCRIPT_DIR/config/rules.yaml

# Get OpenShift DNS name
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-ingress
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}
TYPE="ingress"

CA_DURATION="${CA_DURATION:-60m}"
CA_RENEW_BEFORE="${CA_RENEW_BEFORE:-58m}"
LEAF_DURATION="${LEAF_DURATION:-60m}"
LEAF_RENEW_BEFORE="${LEAF_RENEW_BEFORE:-58m}"
INGRESS_DURATION="${INGRESS_DURATION:-60m}"
INGRESS_RENEW_BEFORE="${INGRESS_RENEW_BEFORE:-10m}"

sed \
  -e "s|CA_DURATION|$CA_DURATION|g" \
  -e "s|CA_RENEW_BEFORE|$CA_RENEW_BEFORE|g" \
  -e "s|LEAF_DURATION|$LEAF_DURATION|g" \
  -e "s|LEAF_RENEW_BEFORE|$LEAF_RENEW_BEFORE|g" \
  -e "s|DNS_HOST|$HOST|g" \
  $SCRIPT_DIR/config/resources-to-monitor.yaml > $SCRIPT_DIR/config/tmp_resources-to-monitor.yaml

# Deploy cert-manager Issuer and Certificates
oc apply -f $SCRIPT_DIR/config/tmp_resources-to-monitor.yaml

# Deploy sample app
sed \
  -e "s|INGRESS_DURATION|$INGRESS_DURATION|g" \
  -e "s|INGRESS_RENEW_BEFORE|$INGRESS_RENEW_BEFORE|g" \
  -e "s|DNS_HOST|$HOST|g" \
  $SCRIPT_DIR/config/cert-manager-example-app.yaml > $SCRIPT_DIR/config/tmp_cert-manager-example-app.yaml
oc apply -f $SCRIPT_DIR/config/tmp_cert-manager-example-app.yaml

# Wait a bit for the deployment to be ready
wait_spinner 15

# Run test with curl
curl --cacert <(oc get secret -n cert-manager-monitor-ns test-client-tls-monitor -o jsonpath='{.data.ca\.crt}' | base64 -d) \
  -v https://$HOST
