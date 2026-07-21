# Vault PKI Demo for cert-manager on OpenShift

This demo uses HashiCorp Vault as the Root CA and cert-manager to manage
certificates on OpenShift. It demonstrates two issuance patterns:

1. **Hybrid PKI** — Vault signs an Intermediate CA, cert-manager issues
   leaf certificates locally (no Vault round-trip per leaf)
2. **Direct issuance** — Vault signs leaf certificates directly from the
   Root CA

The demo validates both certificate chains and deploys two applications
communicating over mTLS.

## Architecture

```
┌─── hashicorp-vault namespace ──────────────────────────────────────┐
│                                                                    │
│  Vault (dev mode)                                                  │
│    ├── pki/       Root CA ("Vault PKI Demo Root CA")               │
│    │     ├── root/sign-intermediate  (CA certs)                    │
│    │     └── sign/vault-leaf-role    (leaf certs)                  │
│    └── auth/kubernetes/                                            │
│          └── role: cert-manager-role                               │
│               bound to: vault-issuer-sa @ vault-pki-demo-ns       │
│                                                                    │
└───────────────────────────┬────────────────────────────────────────┘
                            │ K8s SA token auth
                            │
┌─── vault-pki-demo-ns ────┼────────────────────────────────────────┐
│                           │                                        │
│  vault-issuer-sa + token Secret ──────┘                            │
│                                                                    │
│  ── Path 1: Hybrid PKI (intermediate CA) ──────────────────────── │
│                                                                    │
│  cert-manager Issuer (vault-pki-issuer)                            │
│       │  type: vault  (path: pki/root/sign-intermediate)           │
│       │                                                            │
│       └──issues──▶ Intermediate CA Certificate (isCA: true)        │
│                         ▼                                          │
│                    intermediate-ca-secret                           │
│                         │                                          │
│                         ▼                                          │
│  cert-manager Issuer (intermediate-ca-issuer)                      │
│       │  type: ca  (secretName: intermediate-ca-secret)            │
│       │                                                            │
│       ├──issues──▶ server-cert ──▶ server-tls Secret               │
│       └──issues──▶ client-cert ──▶ client-tls Secret               │
│                                                                    │
│  ── Path 2: Direct leaf from Root CA ──────────────────────────── │
│                                                                    │
│  cert-manager Issuer (vault-pki-leaf-issuer)                       │
│       │  type: vault  (path: pki/sign/vault-leaf-role)             │
│       │                                                            │
│       └──issues──▶ vault-direct-leaf-cert ──▶ vault-direct-tls Secret   │
│                                                                    │
│  ── mTLS demo (uses Path 1 certs) ────────────────────────────── │
│                                                                    │
│  vault-pki-ca-bundle ConfigMap (root + intermediate CA)            │
│       │                                                            │
│       ▼                                                            │
│  nginx (mtls-server) ◀──── mTLS ────▶ client (mtls-client)        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

Must have the following installed:
- `oc`
- `helm`
- `curl`
- `openssl`
- `jq`

Additionally:
- An OpenShift cluster with admin access
- The cert-manager operator available in the OperatorHub

## Steps

1. Make sure to log in with your admin credentials via `oc login` command
2. Run the scripts in order from the `src` folder:

```sh
# Installs Vault (dev mode) and the cert-manager operator
./01_install.sh

# Configures Vault PKI Root CA engine and Kubernetes auth
./02_configure_vault_pki.sh

# Creates the Vault Issuer, Intermediate CA, and leaf certificates
./03_deploy_vault_issuer.sh

# Deploys the mTLS server (nginx) and client, builds CA trust bundle
./04_deploy_example_applications.sh

# Validates the full certificate chain and mTLS connectivity
./05_validate.sh

# Cleanup step. Tears down all demo resources
./06_cleanup.sh
```

## How It Works

### Vault PKI Root CA
1. Vault is installed in dev mode on OpenShift via the HashiCorp Helm chart
2. A PKI secrets engine is enabled at `pki/` and configured as the Root CA
3. A PKI role (`vault-leaf-role`) is created for direct leaf cert issuance
4. Kubernetes auth is enabled so cert-manager can authenticate using a
   ServiceAccount token
5. A policy grants cert-manager access to both `pki/root/sign-intermediate`
   (for CA certs) and `pki/sign/vault-leaf-role` (for direct leaf certs)

### Path 1: Intermediate CA (hybrid PKI)
1. A cert-manager `Issuer` of type `vault` (`vault-pki-issuer`) authenticates
   to Vault and requests certificates via `pki/root/sign-intermediate`
2. An `isCA: true` Certificate resource requests an Intermediate CA certificate
   from Vault — this is the only interaction with Vault for this path
3. A second cert-manager `Issuer` of type `ca` (`intermediate-ca-issuer`)
   uses the Intermediate CA secret to issue leaf certificates locally
4. Leaf certificates (server and client) are issued by the local
   `intermediate-ca-issuer` — no Vault round-trip required
5. Certificate chain: Vault Root CA -> Intermediate CA -> Leaf Cert

### Path 2: Direct leaf certificates
1. A cert-manager `Issuer` of type `vault` (`vault-pki-leaf-issuer`)
   authenticates to Vault and requests certificates via `pki/sign/vault-leaf-role`
2. Leaf certificates are signed directly by the Vault Root CA
3. Every issuance and renewal requires a Vault round-trip
4. Certificate chain: Vault Root CA -> Leaf Cert

### mTLS Communication
1. The **server** (nginx) is configured with `ssl_verify_client on`,
   requiring clients to present a valid certificate
2. The **client** connects using its client certificate and the CA trust
   bundle (containing both root and intermediate CA certificates)
3. A CA trust bundle ConfigMap is created manually from the intermediate
   CA and root CA certificates for both pods to mount

## Troubleshooting

### Vault Issuer not ready
- Check Vault is running: `oc get pods -n hashicorp-vault`
- Check SA token: `oc get secret vault-issuer-token -n vault-pki-demo-ns -o jsonpath='{.data.token}'`
- Check Issuer status: `oc describe issuer vault-pki-issuer -n vault-pki-demo-ns`
- Check Vault auth: `oc exec vault-0 -n hashicorp-vault -- vault read auth/kubernetes/config`

### Intermediate CA not issuing
- Check Vault policy: `oc exec vault-0 -n hashicorp-vault -- vault policy read cert-manager-pki`
- Check CertificateRequest: `oc get certificaterequest -n vault-pki-demo-ns`
- Check cert-manager logs: `oc logs -n cert-manager -l app=cert-manager`

### Leaf certificates not issuing
- Check the intermediate CA Issuer: `oc describe issuer intermediate-ca-issuer -n vault-pki-demo-ns`
- Check that intermediate-ca-secret exists: `oc get secret intermediate-ca-secret -n vault-pki-demo-ns`
- Check leaf cert status: `oc get certificate -n vault-pki-demo-ns`

### mTLS handshake failures
- Check server logs: `oc logs -n vault-pki-demo-ns -l app=mtls-server`
- Verify CA bundle: `oc get configmap vault-pki-ca-bundle -n vault-pki-demo-ns -o jsonpath='{.data.ca-bundle\.crt}' | openssl x509 -noout -subject`
- Verify server cert: `oc get secret server-tls -n vault-pki-demo-ns -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer -subject`

## Disclaimer

This is not guaranteed to work in all environments. Vault is installed
in dev mode which is NOT recommended for production environments. This
demo is intended for learning and development environments only.
