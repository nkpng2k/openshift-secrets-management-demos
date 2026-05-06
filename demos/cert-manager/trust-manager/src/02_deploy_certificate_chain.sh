#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

CA_NS="cert-manager"
SERVER_NS="trust-manager-server-ns"
CLIENT_NS="trust-manager-client-ns"

# Create workload namespaces
oc new-project $SERVER_NS
oc new-project $CLIENT_NS
oc project $CA_NS

# Resolve cluster DNS for Ingress hostname and in-cluster service DNS
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
DNS_HOST=mtls-server.apps.${BASE_DOMAIN}
SVC_HOST=mtls-server.${SERVER_NS}.svc.cluster.local

# Substitute placeholders and apply certificate chain
sed \
  -e "s|CA_NS|$CA_NS|g" \
  -e "s|SERVER_NS|$SERVER_NS|g" \
  -e "s|CLIENT_NS|$CLIENT_NS|g" \
  -e "s|DNS_HOST|$DNS_HOST|g" \
  -e "s|SVC_HOST|$SVC_HOST|g" \
  $SCRIPT_DIR/config/certificate_chain.yaml > $SCRIPT_DIR/config/tmp_certificate_chain.yaml

oc apply -f $SCRIPT_DIR/config/tmp_certificate_chain.yaml

# Wait for CA certificates in cert-manager namespace
echo "Waiting for CA certificates to be issued..."
wait_spinner 10

CA_CERTS=("root-ca" "intermediate-ca")
for CERT in "${CA_CERTS[@]}"; do
  echo "Checking certificate: $CERT (namespace: $CA_NS)"
  READY=$(oc get certificate $CERT -n $CA_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  TIMEOUT=60
  ELAPSED=0
  while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    READY=$(oc get certificate $CERT -n $CA_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  done
  if [[ "$READY" == "True" ]]; then
    echo "  $CERT: Ready"
  else
    echo "  $CERT: NOT Ready (timed out after ${TIMEOUT}s)"
    oc describe certificate $CERT -n $CA_NS
    exit 1
  fi
done

# Wait for leaf certificates in workload namespaces
echo ""
echo "Waiting for leaf certificates to be issued..."

declare -A LEAF_CERTS
LEAF_CERTS[server-cert]=$SERVER_NS
LEAF_CERTS[client-cert]=$CLIENT_NS

for CERT in "${!LEAF_CERTS[@]}"; do
  NS=${LEAF_CERTS[$CERT]}
  echo "Checking certificate: $CERT (namespace: $NS)"
  READY=$(oc get certificate $CERT -n $NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  TIMEOUT=60
  ELAPSED=0
  while [[ "$READY" != "True" && $ELAPSED -lt $TIMEOUT ]]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    READY=$(oc get certificate $CERT -n $NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  done
  if [[ "$READY" == "True" ]]; then
    echo "  $CERT: Ready"
  else
    echo "  $CERT: NOT Ready (timed out after ${TIMEOUT}s)"
    oc describe certificate $CERT -n $NS
    exit 1
  fi
done

echo ""
echo "All certificates issued successfully:"
echo "  CA certificates ($CA_NS):"
oc get certificate -n $CA_NS
echo ""
echo "  Server certificate ($SERVER_NS):"
oc get certificate -n $SERVER_NS
echo ""
echo "  Client certificate ($CLIENT_NS):"
oc get certificate -n $CLIENT_NS
