#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMOS_DIR=$(dirname "$SCRIPT_DIR")
source "$SCRIPT_DIR/ocp.sh"

echo "=== Step 1: Apply operator-level configs ==="
oc apply -f "$DEMOS_DIR/external-secrets-operator/operator/config/eso.yaml"
oc apply -f "$DEMOS_DIR/secrets-store-csi/operator/config/sscsi.yaml"

echo ""
echo "=== Step 2: Configure Vault ==="
SA_ISSUER=$(oc get authentication.config cluster -o json | jq -r .spec.serviceAccountIssuer)
if [[ -z "$SA_ISSUER" ]]; then
  SA_ISSUER="https://kubernetes.default.svc"
fi

oc exec -n hashicorp-vault vault-0 -- sh -c "
vault secrets enable -version=2 kv || true
vault kv put kv/secret password=demo-secret-password-123
vault kv put secret/db-pass password=demo-secret-password-123

vault auth enable kubernetes || true
vault write auth/kubernetes/config \
  issuer=\"$SA_ISSUER\" \
  token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
  kubernetes_host=\"https://\$KUBERNETES_PORT_443_TCP_ADDR:443\" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault policy write eso - <<EOF
path \"*\" {
  capabilities = [\"read\"]
}
EOF
vault write auth/kubernetes/role/eso-role \
  bound_service_account_names=eso-demo-sa \
  bound_service_account_namespaces=eso-demo-ns \
  policies=eso \
  ttl=20m

vault policy write internal-app - <<EOF
path \"secret/data/db-pass\" {
  capabilities = [\"read\"]
}
EOF
vault write auth/kubernetes/role/database \
  bound_service_account_names=sscsi-demo-sa \
  bound_service_account_namespaces=sscsi-demo-ns \
  policies=internal-app \
  ttl=20m
"

echo ""
echo "=== Step 3: Deploy cert-manager demo ==="
oc new-project cert-manager-demo-ns 2>/dev/null || oc project cert-manager-demo-ns

BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-ingress
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}
TYPE="ingress"

CA_DURATION="${CA_DURATION:-60m}"
CA_RENEW_BEFORE="${CA_RENEW_BEFORE:-10m}"
LEAF_DURATION="${LEAF_DURATION:-60m}"
LEAF_RENEW_BEFORE="${LEAF_RENEW_BEFORE:-10m}"

CERT_MANAGER_CONFIG="$DEMOS_DIR/cert-manager/self-signed-ingress/src/config"

sed \
  -e "s|CA_DURATION|$CA_DURATION|g" \
  -e "s|CA_RENEW_BEFORE|$CA_RENEW_BEFORE|g" \
  -e "s|LEAF_DURATION|$LEAF_DURATION|g" \
  -e "s|LEAF_RENEW_BEFORE|$LEAF_RENEW_BEFORE|g" \
  -e "s|DNS_HOST|$HOST|g" \
  -e "s|TYPE|$TYPE|g" \
  "$CERT_MANAGER_CONFIG/cert_manager_crds.yaml" | oc apply -f -

sed \
  -e "s|LEAF_DURATION|$LEAF_DURATION|g" \
  -e "s|LEAF_RENEW_BEFORE|$LEAF_RENEW_BEFORE|g" \
  -e "s|DNS_HOST|$HOST|g" \
  -e "s|TYPE|$TYPE|g" \
  "$CERT_MANAGER_CONFIG/cert_manager_example.yaml" | oc apply -f -

echo "Waiting for cert-manager deployment..."
oc rollout status deployment/hello-openshift-ingress -n cert-manager-demo-ns --timeout=60s
oc wait --for=condition=Ready -n cert-manager-demo-ns certificate --all --timeout=60s
echo "cert-manager demo deployed."

echo ""
echo "=== Step 4: Deploy External Secrets Operator demo ==="
oc new-project eso-demo-ns 2>/dev/null || oc project eso-demo-ns
oc create serviceaccount -n eso-demo-ns eso-demo-sa 2>/dev/null || true

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')
ESO_CONFIG="$DEMOS_DIR/external-secrets-operator/busybox/src/config"

sed \
  -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
  "$ESO_CONFIG/eso_resources.yaml" | oc apply -f -

cat <<'EOFES' | oc apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: vault-external-secret-2
  namespace: eso-demo-ns
spec:
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: vault-secret-example-2
  data:
  - secretKey: password
    remoteRef:
      key: secret
      property: password
EOFES

oc wait --for=condition=Ready -n eso-demo-ns externalsecret --all --timeout=60s

oc apply -f "$ESO_CONFIG/eso_pod_example.yaml"

cat <<'EOFPOD' | oc apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: eso-demo-2
  namespace: eso-demo-ns
spec:
  serviceAccountName: eso-demo-sa
  securityContext:
    fsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - image: busybox:stable
    name: eso-demo-2
    command: ["sh", "-c", "while true; do sleep 3600; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      runAsNonRoot: true
    env:
    - name: DEMO_PWD
      valueFrom:
        secretKeyRef:
          name: vault-secret-example-2
          key: password
    volumeMounts:
    - name: eso-demo-volume
      mountPath: "/mnt/demo-vol"
      readOnly: true
  volumes:
    - name: eso-demo-volume
      secret:
        secretName: vault-secret-example-2
---
kind: Pod
apiVersion: v1
metadata:
  name: eso-demo-3
  namespace: eso-demo-ns
spec:
  serviceAccountName: eso-demo-sa
  securityContext:
    fsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - image: busybox:stable
    name: eso-demo-3
    command: ["sh", "-c", "while true; do sleep 3600; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      runAsNonRoot: true
    env:
    - name: DEMO_PWD
      valueFrom:
        secretKeyRef:
          name: vault-secret-example-2
          key: password
    volumeMounts:
    - name: eso-demo-volume
      mountPath: "/mnt/demo-vol"
      readOnly: true
  volumes:
    - name: eso-demo-volume
      secret:
        secretName: vault-secret-example-2
EOFPOD

oc wait --for=condition=Ready -n eso-demo-ns pod --all --timeout=60s
echo "ESO demo deployed."

echo ""
echo "=== Step 5: Deploy Secrets Store CSI Driver demo ==="
oc new-project sscsi-demo-ns 2>/dev/null || oc project sscsi-demo-ns
oc create serviceaccount -n sscsi-demo-ns sscsi-demo-sa 2>/dev/null || true

SSCSI_CONFIG="$DEMOS_DIR/secrets-store-csi/busybox/src/config"
oc apply -f "$SSCSI_CONFIG/sscsi_resources.yaml"

cat <<'EOFSSCSI' | oc apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: sscsi-demo-2
  namespace: sscsi-demo-ns
spec:
  serviceAccountName: sscsi-demo-sa
  securityContext:
    fsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - image: busybox:stable
    name: sscsi-demo-2
    command: ["sh", "-c", "while true; do sleep 3600; done"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      runAsNonRoot: true
    volumeMounts:
    - name: secrets-store-inline
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "vault-database"
EOFSSCSI

oc wait --for=condition=Ready -n sscsi-demo-ns pod --all --timeout=120s
echo "SSCSI demo deployed."

echo ""
echo "=== All demos deployed ==="
echo "Namespaces: cert-manager-demo-ns, eso-demo-ns, sscsi-demo-ns"
