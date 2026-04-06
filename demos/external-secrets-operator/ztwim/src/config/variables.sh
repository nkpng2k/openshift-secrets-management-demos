#!/bin/bash

# ZTWIM / SPIFFE
SPIRE_TRUST_DOMAIN="cluster.demo"
SPIRE_NAMESPACE="zero-trust-workload-identity-manager"
SPIRE_AGENT_IMAGE="registry.redhat.io/zero-trust-workload-identity-manager/spiffe-spire-agent-rhel9@sha256:54865d9de74a500528dcef5c24dfe15c0baee8df662e76459e83bf9921dfce4e"

# ESO (upstream Helm)
ESO_NAMESPACE="external-secrets"
ESO_SERVICE_ACCOUNT="external-secrets"
ESO_HELM_REPO="external-secrets"
ESO_HELM_REPO_URL="https://charts.external-secrets.io"
ESO_HELM_CHART_VERSION="2.2.0"

# Team namespaces
TEAM_A_NAMESPACE="team-a"
TEAM_B_NAMESPACE="team-b"

# Vault
VAULT_JWT_AUTH_PATH="jwt"
HASHICORP_HELM_REPO="hashicorp"
HASHICORP_HELM_REPO_URL="https://helm.releases.hashicorp.com"
VAULT_IMAGE_REPO="registry.connect.redhat.com/hashicorp/vault"
VAULT_IMAGE_TAG="1.20.2-ubi"
VAULT_CSI_IMAGE_REPO="registry.connect.redhat.com/hashicorp/vault-csi-provider"
VAULT_CSI_IMAGE_TAG="1.6.0-ubi"
