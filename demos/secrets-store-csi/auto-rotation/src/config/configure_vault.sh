#!/bin/bash

vault kv put secret/db-pass password="demo-secret-password-123"
vault auth enable kubernetes
vault write auth/kubernetes/config \
  issuer="SA_ISSUER" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault policy write internal-app - <<EOF
path "secret/data/db-pass" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/database \
  bound_service_account_names=sscsi-demo-sa \
  bound_service_account_namespaces=sscsi-demo-ns \
  policies=internal-app \
  ttl=20m
