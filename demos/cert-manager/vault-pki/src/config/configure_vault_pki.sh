#!/bin/bash
# Vault PKI Configuration Script
# Runs inside the vault-0 pod via: oc exec vault-0 -- bash -c "$(cat ...)"
#
# Sets up:
#   1. Root CA PKI engine (private key stays in Vault)
#   2. PKI role for direct leaf certificate issuance
#   3. Kubernetes auth so cert-manager can authenticate to Vault
#   4. Policy granting access to sign-intermediate and sign/<role>

# --- Root CA PKI Engine ---

vault secrets enable pki

vault secrets tune -max-lease-ttl=87600h pki

vault write -field=certificate pki/root/generate/internal \
  common_name="Vault PKI Demo Root CA" \
  issuer_name="root-ca" \
  ttl=87600h > /tmp/root_ca.crt

vault write pki/config/urls \
  issuing_certificates="http://vault.hashicorp-vault.svc.cluster.local:8200/v1/pki/ca" \
  crl_distribution_points="http://vault.hashicorp-vault.svc.cluster.local:8200/v1/pki/crl"

# --- PKI Role for direct leaf certificates ---

vault write pki/roles/vault-leaf-role \
  allow_any_name=true \
  allow_subdomains=true \
  allow_bare_domains=true \
  enforce_hostnames=false \
  allow_ip_sans=true \
  server_flag=true \
  client_flag=true \
  key_type=any \
  max_ttl=8760h \
  require_cn=false

# --- Kubernetes Auth ---

vault auth enable kubernetes

vault write auth/kubernetes/config \
  issuer="SA_ISSUER" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# --- Policy for cert-manager ---

vault policy write cert-manager-pki - <<EOF
path "pki/root/sign-intermediate" {
  capabilities = ["create", "update"]
}
path "pki/sign/vault-leaf-role" {
  capabilities = ["create", "update"]
}
EOF

# --- Kubernetes Auth Role ---

vault write auth/kubernetes/role/cert-manager-role \
  bound_service_account_names=CERT_MANAGER_SA \
  bound_service_account_namespaces=VAULT_ISSUER_NS \
  policies=cert-manager-pki \
  ttl=20m
