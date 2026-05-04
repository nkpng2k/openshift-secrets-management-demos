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

echo "=== Certificate ==="
oc get certificate -n cert-manager-acme-ns
CERT_READY=$(oc get certificate/acme-certificate -n cert-manager-acme-ns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [[ "$CERT_READY" == "True" ]]; then
  echo "PASS: Certificate is Ready"
else
  echo "FAIL: Certificate is not Ready"
  oc describe certificate acme-certificate -n cert-manager-acme-ns
  exit 1
fi

echo ""
echo "=== CertificateRequest ==="
oc get certificaterequest -n cert-manager-acme-ns
CR_READY=$(oc get certificaterequest -n cert-manager-acme-ns -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
CR_APPROVED=$(oc get certificaterequest -n cert-manager-acme-ns -o jsonpath='{.items[0].status.conditions[?(@.type=="Approved")].status}')
if [[ "$CR_READY" == "True" && "$CR_APPROVED" == "True" ]]; then
  echo "PASS: CertificateRequest is Approved and Ready"
else
  echo "FAIL: CertificateRequest is not in expected state (Ready=$CR_READY, Approved=$CR_APPROVED)"
  oc describe certificaterequest -n cert-manager-acme-ns
  exit 1
fi

echo ""
echo "=== Order ==="
oc get order -n cert-manager-acme-ns
ORDER_STATE=$(oc get order -n cert-manager-acme-ns -o jsonpath='{.items[0].status.state}')
if [[ "$ORDER_STATE" == "valid" ]]; then
  echo "PASS: Order state is 'valid' (Let's Encrypt fulfilled the request)"
else
  echo "FAIL: Order state is '$ORDER_STATE' (expected 'valid')"
  oc describe order -n cert-manager-acme-ns
  exit 1
fi

echo ""
echo "=== Challenge (captured during issuance) ==="
if [[ -f "$SCRIPT_DIR/config/tmp_challenge_details.txt" ]]; then
  cat $SCRIPT_DIR/config/tmp_challenge_details.txt
else
  echo "No captured Challenge details found."
  echo "Challenges are ephemeral and cleaned up after the Order is fulfilled."
fi

if [[ -f "$SCRIPT_DIR/config/tmp_challenge_events.txt" ]]; then
  echo ""
  echo "Challenge-related events:"
  cat $SCRIPT_DIR/config/tmp_challenge_events.txt
fi

echo ""
echo "=== TLS Secret ==="
SECRET_EXISTS=$(oc get secret acme-tls -n cert-manager-acme-ns -o name 2>/dev/null)
if [[ -n "$SECRET_EXISTS" ]]; then
  echo "PASS: Secret 'acme-tls' exists"
  echo ""
  echo "Certificate details from secret:"
  oc get secret acme-tls -n cert-manager-acme-ns -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer -subject -dates
else
  echo "FAIL: Secret 'acme-tls' not found"
  exit 1
fi

# Wait for the router to reload with the new certificate
wait_spinner 10

echo ""
echo "=== TLS Connectivity ==="
if [[ "$ACME_ISSUER" == "letsencrypt-production" ]]; then
  echo "Testing with production certificate (trusted by default):"
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' https://$HOST)
else
  echo "Testing with staging certificate (not publicly trusted, using -k):"
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -k https://$HOST)
fi

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "PASS: HTTPS request returned HTTP $HTTP_CODE"
else
  echo "FAIL: HTTPS request returned HTTP $HTTP_CODE (expected 200)"
  exit 1
fi

echo ""
echo "Certificate chain (via openssl):"
openssl s_client -connect $HOST:443 -servername $HOST < /dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates

echo ""
echo "=== All validations passed ==="
