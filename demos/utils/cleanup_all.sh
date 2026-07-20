#!/bin/bash
set -uo pipefail

echo "=== Cleaning up demo namespaces ==="
oc delete project cert-manager-demo-ns --ignore-not-found
oc delete project eso-demo-ns --ignore-not-found
oc delete project sscsi-demo-ns --ignore-not-found

echo ""
echo "=== Cleaning up cluster-scoped resources ==="
oc delete clusterrolebinding eso-demo-crb --ignore-not-found

echo ""
echo "=== Cleaning up operator configs ==="
oc delete externalsecretsconfig cluster --ignore-not-found
oc delete clustercsidriver secrets-store.csi.k8s.io --ignore-not-found

echo ""
echo "=== Cleaning up Vault ==="
oc exec -n hashicorp-vault vault-0 -- sh -c '
vault secrets disable kv/ 2>/dev/null || true
vault auth disable kubernetes/ 2>/dev/null || true
vault policy delete eso 2>/dev/null || true
vault policy delete internal-app 2>/dev/null || true
vault kv metadata delete secret/db-pass 2>/dev/null || true
' 2>/dev/null || true

echo ""
echo "=== Cleanup complete ==="
oc project default 2>/dev/null || true
