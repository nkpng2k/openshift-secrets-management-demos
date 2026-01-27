#!/bin/bash

vault auth enable kubernetes
vault write auth/kubernetes/config \
  issuer="https://rh-oidc.s3.us-east-1.amazonaws.com/27bd6cg0vs7nn08mue83fbof94dj4m9a" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault policy write eso - <<EOF
path "*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/eso-role \
  bound_service_account_names=eso-demo-sa \
  bound_service_account_namespaces=eso-demo-ns \
  policies=eso \
  ttl=20m

vault secrets enable -version=2 kv
vault kv put kv/argodemo private-key=/tmp/key.pem
vault kv put kv/secret password=demo-secret-password-123
