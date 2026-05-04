#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/acme-ingress/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Get OpenShift DNS name
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-acme
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}

# Default to production issuer; set ACME_ISSUER=letsencrypt-staging for testing
ACME_ISSUER=${ACME_ISSUER:-letsencrypt-production}

sed \
  -e "s|DNS_HOST|$HOST|g" \
  -e "s|ACME_ISSUER|$ACME_ISSUER|g" \
  $SCRIPT_DIR/config/acme_example.yaml > $SCRIPT_DIR/config/tmp_acme_example.yaml
oc apply -f $SCRIPT_DIR/config/tmp_acme_example.yaml

# Wait for deployment to be ready
wait_spinner 15

# Poll for certificate readiness while capturing Challenge details
echo "Waiting for ACME certificate to be issued..."
CHALLENGE_CAPTURED=false
TIMEOUT=120
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CERT_READY=$(oc get certificate/acme-certificate -n cert-manager-acme-ns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

  if [[ "$CERT_READY" == "True" ]]; then
    echo "Certificate is ready."
    break
  fi

  # Capture Challenge details while they still exist
  if [[ "$CHALLENGE_CAPTURED" == "false" ]]; then
    CHALLENGES=$(oc get challenge -n cert-manager-acme-ns --no-headers 2>/dev/null)
    if [[ -n "$CHALLENGES" ]]; then
      echo ""
      echo "--- ACME Challenge detected ---"
      oc get challenge -n cert-manager-acme-ns
      echo ""
      oc describe challenge -n cert-manager-acme-ns > $SCRIPT_DIR/config/tmp_challenge_details.txt
      oc get events -n cert-manager-acme-ns --field-selector reason=Started --sort-by='.lastTimestamp' > $SCRIPT_DIR/config/tmp_challenge_events.txt 2>/dev/null
      CHALLENGE_CAPTURED=true
      echo "Challenge details saved."
    fi
  fi

  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "ERROR: Timed out waiting for certificate to be ready."
  oc describe certificate acme-certificate -n cert-manager-acme-ns
  exit 1
fi

echo ""
echo "Certificate status:"
oc get certificate -n cert-manager-acme-ns
