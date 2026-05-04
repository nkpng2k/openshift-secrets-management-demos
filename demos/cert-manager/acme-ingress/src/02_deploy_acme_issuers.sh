#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Validate required ACME_EMAIL environment variable
if [[ -z "$ACME_EMAIL" ]]; then
  echo "ERROR: ACME_EMAIL environment variable is not set."
  echo "Please set it to a valid email for Let's Encrypt registration:"
  echo "  export ACME_EMAIL=you@example.com"
  exit 1
fi

# Default to production issuer; set ACME_ISSUER=letsencrypt-staging for testing
ACME_ISSUER=${ACME_ISSUER:-letsencrypt-production}

# Select the issuer template based on ACME_ISSUER
case "$ACME_ISSUER" in
  letsencrypt-staging)
    ISSUER_TEMPLATE="$SCRIPT_DIR/config/acme_issuer_staging.yaml"
    ;;
  letsencrypt-production)
    ISSUER_TEMPLATE="$SCRIPT_DIR/config/acme_issuer_production.yaml"
    ;;
  *)
    echo "ERROR: Invalid ACME_ISSUER value: $ACME_ISSUER"
    echo "Must be 'letsencrypt-staging' or 'letsencrypt-production'"
    exit 1
    ;;
esac

# Create new demo project
oc new-project cert-manager-acme-ns
oc project cert-manager-acme-ns

# Determine the IngressClass name
# OpenShift 4.14+ uses "openshift-default"; older versions may differ
INGRESS_CLASS=${INGRESS_CLASS:-openshift-default}

sed \
  -e "s|ACME_EMAIL|$ACME_EMAIL|g" \
  -e "s|INGRESS_CLASS|$INGRESS_CLASS|g" \
  $ISSUER_TEMPLATE > $SCRIPT_DIR/config/tmp_acme_issuer.yaml

# Deploy ACME Issuer
oc apply -f $SCRIPT_DIR/config/tmp_acme_issuer.yaml

echo ""
echo "$ACME_ISSUER Issuer deployed."
echo "You can check Issuer status with: oc get issuer -n cert-manager-acme-ns"
