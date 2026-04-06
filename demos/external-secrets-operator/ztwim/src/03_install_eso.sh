#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/ztwim/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh
source $SCRIPT_DIR/config/variables.sh

echo "=== Installing ESO via Helm (with SPIFFE sidecars) ==="

# Create ESO namespace
oc new-project $ESO_NAMESPACE

# Deploy jwt-fetch-script ConfigMap (must exist before Helm install)
sed \
  -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
  $SCRIPT_DIR/config/jwt_fetch_script.yaml > $SCRIPT_DIR/config/tmp_jwt_fetch_script.yaml
oc apply -f $SCRIPT_DIR/config/tmp_jwt_fetch_script.yaml

# Template ESO Helm values
sed \
  -e "s|SPIRE_AGENT_IMAGE|$SPIRE_AGENT_IMAGE|g" \
  $SCRIPT_DIR/config/eso_helm_values.yaml > $SCRIPT_DIR/config/tmp_eso_helm_values.yaml

# Install ESO
helm repo add $ESO_HELM_REPO $ESO_HELM_REPO_URL
helm repo update
helm install external-secrets $ESO_HELM_REPO/external-secrets \
  -n $ESO_NAMESPACE \
  --version $ESO_HELM_CHART_VERSION \
  --values $SCRIPT_DIR/config/tmp_eso_helm_values.yaml

echo "Waiting for ESO controller pod..."
oc wait --for=condition=ready --timeout=300s \
  pod -l app.kubernetes.io/name=external-secrets -n $ESO_NAMESPACE

echo "Waiting for ESO webhook pod..."
oc wait --for=condition=ready --timeout=300s \
  pod -l app.kubernetes.io/name=external-secrets-webhook -n $ESO_NAMESPACE

echo "=== Deploying ESO Resources (ClusterSPIFFEID, Service, Webhook Generator, JWT ExternalSecret) ==="

sed \
  -e "s|TRUST_DOMAIN|$SPIRE_TRUST_DOMAIN|g" \
  -e "s|ESO_NAMESPACE|$ESO_NAMESPACE|g" \
  $SCRIPT_DIR/config/eso_resources.yaml > $SCRIPT_DIR/config/tmp_eso_resources.yaml
oc apply -f $SCRIPT_DIR/config/tmp_eso_resources.yaml

echo "Waiting for spiffe-jwt Secret..."
RETRIES=0
MAX_RETRIES=60
while ! oc get secret spiffe-jwt -n $ESO_NAMESPACE &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    echo "ERROR: Timed out waiting for spiffe-jwt Secret"
    echo "Check jwt-fetcher logs: oc logs -n $ESO_NAMESPACE deploy/external-secrets -c jwt-fetcher"
    exit 1
  fi
  sleep 5
done
echo "spiffe-jwt Secret created."

echo "ESO installation complete."
