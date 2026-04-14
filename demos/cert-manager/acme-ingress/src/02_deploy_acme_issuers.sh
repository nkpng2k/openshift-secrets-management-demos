#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Validate required ACME_EMAIL environment variable
if [[ -z "$ACME_EMAIL" ]]; then
  echo "ERROR: ACME_EMAIL environment variable is not set."
  echo "Please set it to a valid email for Let's Encrypt registration:"
  echo "  export ACME_EMAIL=you@example.com"
  exit 1
fi

# Create new demo project
oc new-project cert-manager-acme-ns
oc project cert-manager-acme-ns

# Get OpenShift DNS name
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-acme
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}

# Determine the IngressClass name
# OpenShift 4.14+ uses "openshift-default"; older versions may differ
INGRESS_CLASS=${INGRESS_CLASS:-openshift-default}

sed \
  -e "s|DNS_HOST|$HOST|g" \
  -e "s|ACME_EMAIL|$ACME_EMAIL|g" \
  -e "s|INGRESS_CLASS|$INGRESS_CLASS|g" \
  $SCRIPT_DIR/config/acme_issuers.yaml > $SCRIPT_DIR/config/tmp_acme_issuers.yaml

# Deploy ACME Issuers and Certificate
oc apply -f $SCRIPT_DIR/config/tmp_acme_issuers.yaml

echo ""
echo "Issuers and Certificate deployed. Checking status..."
echo "You can check Issuer status with: oc get issuer -n cert-manager-acme-ns"
