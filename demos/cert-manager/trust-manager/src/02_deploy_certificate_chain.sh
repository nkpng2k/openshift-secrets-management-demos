#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

DEMO_NS="trust-manager-demo-ns"

# Create demo namespace
oc new-project $DEMO_NS
oc project $DEMO_NS

# Resolve cluster DNS for Ingress hostname and in-cluster service DNS
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
DNS_HOST=mtls-server.apps.${BASE_DOMAIN}
SVC_HOST=mtls-server.${DEMO_NS}.svc.cluster.local

# Substitute placeholders and apply certificate chain
sed \
  -e "s|DEMO_NS|$DEMO_NS|g" \
  -e "s|DNS_HOST|$DNS_HOST|g" \
  -e "s|SVC_HOST|$SVC_HOST|g" \
  $SCRIPT_DIR/config/certificate_chain.yaml > $SCRIPT_DIR/config/tmp_certificate_chain.yaml

oc apply -f $SCRIPT_DIR/config/tmp_certificate_chain.yaml

# Wait for all certificates to reach Ready state
echo "Waiting for certificates to be issued..."
wait_spinner 10

CERTS=("root-ca" "intermediate-ca" "server-cert" "client-cert")
for CERT in "${CERTS[@]}"; do
  echo "Checking certificate: $CERT"
  READY=$(oc get certificate $CERT -n $DEMO_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  TIMEOUT=60
  ELAPSED=0
  while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    READY=$(oc get certificate $CERT -n $DEMO_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  done
  if [[ "$READY" == "True" ]]; then
    echo "  $CERT: Ready"
  else
    echo "  $CERT: NOT Ready (timed out after ${TIMEOUT}s)"
    oc describe certificate $CERT -n $DEMO_NS
    exit 1
  fi
done

echo ""
echo "All certificates issued successfully:"
oc get certificate -n $DEMO_NS
