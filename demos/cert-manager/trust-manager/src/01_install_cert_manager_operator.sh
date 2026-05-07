#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="cert-manager/trust-manager/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

DEMO_SRC_DIR="trust-manager/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Detect OpenShift version
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}')
OCP_MINOR=$(echo "$OCP_VERSION" | grep -oE '^[0-9]+\.[0-9]+')
echo "Detected OpenShift version: $OCP_VERSION"

if [[ "$OCP_MINOR" == "4.21" ]]; then
  # OpenShift 4.21 requires TechPreviewNoUpgrade for trust-manager
  if ! oc get featuregate cluster -o yaml 2>/dev/null | grep -q "TechPreviewNoUpgrade"; then
    echo ""
    echo "ERROR: OpenShift $OCP_VERSION requires TechPreviewNoUpgrade FeatureGate for trust-manager."
    echo ""
    echo "Enable it with:"
    echo "  oc patch featuregate/cluster --type=merge -p '{\"spec\":{\"featureSet\":\"TechPreviewNoUpgrade\"}}'"
    echo ""
    echo "WARNING: This is an irreversible change. Wait for the rolling node update to"
    echo "         complete before re-running this script."
    exit 1
  fi
  echo "TechPreviewNoUpgrade FeatureGate is enabled."

  # Copy operator YAML and add trust-manager env to the Subscription
  cp $OPERATOR_DIR/config/operator.yaml $SCRIPT_DIR/config/tmp_operator.yaml
  sed -i'' -e '/installPlanApproval: Automatic/a\
  config:\
    env:\
    - name: UNSUPPORTED_ADDON_FEATURES\
      value: "TrustManager=true"' $SCRIPT_DIR/config/tmp_operator.yaml

  # Create project and apply modified operator config
  oc new-project cert-manager-operator
  oc project cert-manager-operator
  oc apply -f $SCRIPT_DIR/config/tmp_operator.yaml

  # Wait for operator
  wait_spinner 5
  await_csv_ready cert-manager-operator
  POD_NAME=$(get_pod_name cert cert-manager-operator)
  await_pod_ready $POD_NAME cert-manager-operator

  # Create TrustManager CR to deploy trust-manager
  echo "Creating TrustManager CR..."
  oc apply -f $SCRIPT_DIR/config/trust_manager.yaml

  # Wait for trust-manager deployment to be created by the operator
  echo "Waiting for trust-manager deployment to appear..."
  TIMEOUT=120
  ELAPSED=0
  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if oc get deployment/trust-manager -n cert-manager &>/dev/null; then
      echo "trust-manager deployment found."
      break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    printf "."
  done
  echo ""

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "ERROR: trust-manager deployment was not created within ${TIMEOUT}s."
    echo "Check operator logs: oc logs -n cert-manager-operator -l name=cert-manager-operator"
    exit 1
  fi

  # Wait for trust-manager deployment to be ready
  echo "Waiting for trust-manager to become ready..."
  if ! oc wait --for=condition=Available deployment/trust-manager -n cert-manager --timeout=120s; then
    echo "ERROR: trust-manager deployment did not become ready."
    exit 1
  fi
  echo "trust-manager is running."
else
  # For non-4.21 clusters, use the standard install
  /bin/bash $OPERATOR_DIR/install.sh
fi
