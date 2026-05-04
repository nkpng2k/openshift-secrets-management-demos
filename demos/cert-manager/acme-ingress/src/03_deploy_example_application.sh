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

# Wait for ACME certificate to be issued (HTTP-01 challenge may take 1-2 minutes)
echo "Waiting for ACME certificate to be issued..."
oc wait --for=condition=Ready certificate/acme-certificate -n cert-manager-acme-ns --timeout=120s

echo ""
echo "Certificate status:"
oc get certificate -n cert-manager-acme-ns

echo ""
echo "--- Verification ---"
if [[ "$ACME_ISSUER" == "letsencrypt-production" ]]; then
  # Production certs are trusted by default
  echo "Testing with production certificate (trusted by default):"
  curl -v https://$HOST
else
  # Staging certs are NOT trusted; use -k to skip verification
  echo "Testing with staging certificate (not publicly trusted, using -k):"
  curl -k -v https://$HOST
fi

echo ""
echo "You can also verify the certificate chain with openssl:"
echo "  openssl s_client -connect $HOST:443 -servername $HOST < /dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates"
