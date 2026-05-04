#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

DEMO_NS="trust-manager-demo-ns"
oc project $DEMO_NS

# Resolve DNS for server hostname
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
DNS_HOST=mtls-server.apps.${BASE_DOMAIN}

# Deploy the mTLS server (nginx)
sed \
  -e "s|DEMO_NS|$DEMO_NS|g" \
  -e "s|DNS_HOST|$DNS_HOST|g" \
  $SCRIPT_DIR/config/server_app.yaml > $SCRIPT_DIR/config/tmp_server_app.yaml

oc apply -f $SCRIPT_DIR/config/tmp_server_app.yaml

# Create the validation script ConfigMap (substitute namespace placeholder)
sed \
  -e "s|DEMO_NS|$DEMO_NS|g" \
  $SCRIPT_DIR/config/validate_mtls.sh > $SCRIPT_DIR/config/tmp_validate_mtls.sh

oc create configmap mtls-validation-script \
  --from-file=validate_mtls.sh=$SCRIPT_DIR/config/tmp_validate_mtls.sh \
  -n $DEMO_NS --dry-run=client -o yaml | oc apply -f -

# Deploy the mTLS client
sed \
  -e "s|DEMO_NS|$DEMO_NS|g" \
  $SCRIPT_DIR/config/client_app.yaml > $SCRIPT_DIR/config/tmp_client_app.yaml

oc apply -f $SCRIPT_DIR/config/tmp_client_app.yaml

# Wait for deployments to be ready
echo "Waiting for server and client deployments..."
wait_spinner 15

oc wait --for=condition=Available deployment/mtls-server -n $DEMO_NS --timeout=60s
oc wait --for=condition=Available deployment/mtls-client -n $DEMO_NS --timeout=60s

echo ""
echo "Deployments ready:"
oc get pods -n $DEMO_NS

# Quick mTLS test from client pod
echo ""
echo "Running quick mTLS connectivity test..."
CLIENT_POD=$(oc get pods -n $DEMO_NS -l app=mtls-client --no-headers | awk '{print $1}')
HTTP_CODE=$(oc exec $CLIENT_POD -n $DEMO_NS -- \
  curl -s -o /dev/null -w '%{http_code}' \
  --cert /etc/client-tls/tls.crt \
  --key /etc/client-tls/tls.key \
  --cacert /etc/trust/ca-bundle.crt \
  https://mtls-server.${DEMO_NS}.svc.cluster.local)

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "mTLS connectivity test PASSED (HTTP $HTTP_CODE)"
else
  echo "mTLS connectivity test FAILED (HTTP $HTTP_CODE)"
  exit 1
fi
