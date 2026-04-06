#!/bin/bash

vault auth enable -path=VAULT_JWT_AUTH_PATH jwt

vault write auth/VAULT_JWT_AUTH_PATH/config \
  oidc_discovery_url="OIDC_DISCOVERY_URL" \
  default_role=""

vault policy write team-a-policy - <<EOF
path "kv/data/TEAM_A_NAMESPACE/*" {
  capabilities = ["read"]
}
EOF

vault policy write team-b-policy - <<EOF
path "kv/data/TEAM_B_NAMESPACE/*" {
  capabilities = ["read"]
}
EOF

# Both roles share the same bound_subject (ESO controller's SPIFFE ID).
# Isolation is enforced by different token_policies per role.
vault write auth/VAULT_JWT_AUTH_PATH/role/TEAM_A_NAMESPACE-role \
  role_type="jwt" \
  bound_audiences="vault" \
  bound_subject="spiffe://TRUST_DOMAIN/ns/ESO_NAMESPACE/sa/ESO_SERVICE_ACCOUNT" \
  user_claim="sub" \
  token_policies="team-a-policy" \
  token_ttl="1h"

vault write auth/VAULT_JWT_AUTH_PATH/role/TEAM_B_NAMESPACE-role \
  role_type="jwt" \
  bound_audiences="vault" \
  bound_subject="spiffe://TRUST_DOMAIN/ns/ESO_NAMESPACE/sa/ESO_SERVICE_ACCOUNT" \
  user_claim="sub" \
  token_policies="team-b-policy" \
  token_ttl="1h"

# SecretStore roles: each team has its own SPIFFE identity.
# The ESO controller pod is registered with per-team SPIFFE IDs
# via separate ClusterSPIFFEID resources.
vault write auth/VAULT_JWT_AUTH_PATH/role/TEAM_A_NAMESPACE-local-role \
  role_type="jwt" \
  bound_audiences="vault" \
  bound_subject="spiffe://TRUST_DOMAIN/eso/TEAM_A_NAMESPACE" \
  user_claim="sub" \
  token_policies="team-a-policy" \
  token_ttl="1h"

vault write auth/VAULT_JWT_AUTH_PATH/role/TEAM_B_NAMESPACE-local-role \
  role_type="jwt" \
  bound_audiences="vault" \
  bound_subject="spiffe://TRUST_DOMAIN/eso/TEAM_B_NAMESPACE" \
  user_claim="sub" \
  token_policies="team-b-policy" \
  token_ttl="1h"

vault secrets enable -version=2 kv
vault kv put kv/TEAM_A_NAMESPACE/credentials username=team-a-user password=s3cret-team-a-456
vault kv put kv/TEAM_B_NAMESPACE/credentials username=team-b-user password=s3cret-team-b-789
