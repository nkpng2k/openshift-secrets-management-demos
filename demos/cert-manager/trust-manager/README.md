# Trust-Manager mTLS Demo for OpenShift

This demo uses cert-manager and trust-manager to establish a private PKI
on OpenShift, distribute trust material across namespaces, and deploy two
applications communicating over mTLS in separate namespaces.

The architecture mirrors a realistic multi-tenant pattern:
- **CA hierarchy** lives in the `cert-manager` namespace (the trust-manager
  trusted namespace), with a **ClusterIssuer** that any namespace can use
  to request leaf certificates
- A **server** namespace runs an nginx mTLS server
- A **client** namespace runs a client that authenticates to the server
- **trust-manager** distributes the CA trust bundle to both workload
  namespaces automatically

The demo validates the full chain of trust and demonstrates that
trust-manager automatically updates the trust bundle when the
intermediate CA certificate is renewed by cert-manager.

trust-manager is a Technology Preview component of the Red Hat
cert-manager operator for OpenShift 4.21 (cert-manager 1.19).

## Architecture

```
┌─── cert-manager namespace (trustNamespace) ────────────────────────────┐
│                                                                        │
│  SelfSigned Issuer ──issues──▶ Root CA Certificate ──▶ root-ca-secret ─┼──┐
│                                      │                                 │  │
│                                      ▼                                 │  │
│                              Root CA Issuer                            │  │
│                                      │                                 │  │
│                                      ▼                                 │  │
│                        Intermediate CA Certificate                     │  │
│                                      │                                 │  │
│                                      ▼                                 │  │
│                          intermediate-ca-secret ───────────────────────┼──┤
│                                      │                                 │  │
└──────────────────────────────────────┼─────────────────────────────────┘  │
                                       │                                    │
              ┌────────────────────────┘                                    │
              ▼                                                             │
   ClusterIssuer                                                            │
   (intermediate-ca-cluster-issuer)                                         │
              │                                                             │
              ├──────────────────────┐                                      │
              ▼                      ▼                                      │
┌─── trust-manager-server-ns ──┐  ┌─── trust-manager-client-ns ──┐          │
│                              │  │                              │          │
│  Server Certificate          │  │  Client Certificate          │          │
│       ▼                      │  │       ▼                      │          │
│  server-tls secret           │  │  client-tls secret           │          │
│                              │  │                              │          │
│  nginx Deployment ◀── mTLS ──┼──┼── Client Deployment          │          │
│       ▲                      │  │       ▲                      │          │
│       │                      │  │       │                      │          │
│  demo-trust-bundle ConfigMap │  │  demo-trust-bundle ConfigMap │          │
│       ▲                      │  │       ▲                      │          │
└───────┼──────────────────────┘  └───────┼──────────────────────┘          │
        │                                 │                                 │
        └──────────┐    ┌─────────────────┘                                 │
                   │    │                                                   │
              trust-manager ◀───────────────────────────────────────────────┘
           (Bundle distribution)
```

## Prerequisites

Must have the following installed:
- `oc`
- `curl`
- `openssl`

Additionally:
- An OpenShift 4.21+ cluster with admin access
- The `TechPreviewNoUpgrade` FeatureGate must be enabled on the cluster

### Enabling TechPreviewNoUpgrade

> **WARNING:** Enabling `TechPreviewNoUpgrade` is an **irreversible** change.
> It enables Technology Preview features and prevents minor version upgrades.
> Do **NOT** apply this on a production cluster.

```sh
oc patch featuregate/cluster --type=merge -p '{"spec":{"featureSet":"TechPreviewNoUpgrade"}}'
```

This triggers a rolling update of all nodes, which can take 30-60 minutes
depending on cluster size. Wait for the update to complete:

```sh
oc get clusterversion
oc get nodes
```

All nodes should show `Ready` and the cluster version should show
`Available=True, Progressing=False` before proceeding.

## Steps

1. Make sure to log in with your admin credentials via `oc login` command
2. Run the scripts in order from the `src` folder:

```sh
# Installs the cert-manager operator with trust-manager enabled
./01_install_cert_manager_operator.sh

# Deploys the CA hierarchy (root CA, intermediate CA) in cert-manager namespace,
# creates a ClusterIssuer, and issues leaf certs in server/client namespaces
./02_deploy_certificate_chain.sh

# Creates a trust-manager Bundle and distributes the CA trust bundle
# to both workload namespaces
./03_deploy_trust_bundle.sh

# Deploys the mTLS server (nginx) and client in separate namespaces,
# validates cross-namespace mTLS connectivity
./04_deploy_example_applications.sh

# Validates the full chain of trust (certificate chain, trust bundle, mTLS)
./05_validate_chain_of_trust.sh

# Demonstrates automatic trust bundle rotation when the intermediate CA renews
# NOTE: This script waits for natural certificate renewal (~5 minutes)
./06_demo_trust_bundle_rotation.sh

# Cleanup step. Tears down all demo resources (FeatureGate cannot be reverted)
./07_cleanup.sh
```

## How It Works

### Certificate Chain
1. A self-signed Issuer in the `cert-manager` namespace bootstraps a Root CA
2. The Root CA issues an Intermediate CA certificate (short-lived: 1h10m
   duration for the rotation demo)
3. A **ClusterIssuer** backed by the Intermediate CA allows any namespace to
   request leaf certificates
4. Two leaf certificates are issued via the ClusterIssuer:
   - A **server** certificate (`server auth`) in `trust-manager-server-ns`
   - A **client** certificate (`client auth`) in `trust-manager-client-ns`

### Trust Distribution
1. A trust-manager `Bundle` resource sources CA certificates from:
   - The intermediate CA secret (in `cert-manager`, the trustNamespace)
   - The root CA secret (in `cert-manager`, the trustNamespace)
   - The OpenShift cluster's default CAs (`useDefaultCAs: true`)
2. trust-manager distributes these as a ConfigMap (`demo-trust-bundle`) to
   all namespaces labeled `trust.cert-manager.io/inject: "true"`
3. Both the server and client pods mount this ConfigMap for TLS trust validation

### mTLS Communication
1. The **server** (nginx in `trust-manager-server-ns`) is configured with
   `ssl_verify_client on`, requiring clients to present a valid certificate
2. The **client** (in `trust-manager-client-ns`) connects cross-namespace
   using its client certificate and the trust bundle as the CA
3. The trust bundle enables both sides: the client trusts the server's
   certificate, and the server trusts the client's certificate

### Automatic Rotation
1. The intermediate CA has a short duration (1h10m) with early renewal
   (1h before expiry)
2. When cert-manager renews the intermediate CA, the secret is updated
3. trust-manager detects the secret change and automatically updates the
   trust bundle ConfigMap in all target namespaces
4. Pods with the ConfigMap volume receive the update via kubelet sync (~60s)

## Troubleshooting

### trust-manager pod not appearing
- Verify FeatureGate: `oc get featuregate cluster -o jsonpath='{.spec.featureSet}'`
- Check operator logs: `oc logs -n cert-manager-operator -l name=cert-manager-operator`
- Check for trust-manager pods: `oc get pods -n cert-manager | grep trust-manager`

### Bundle not distributing ConfigMaps
- Check Bundle status: `oc get bundle demo-trust-bundle -o yaml`
- Verify namespace labels: `oc get ns -l trust.cert-manager.io/inject=true`
- Check trust-manager logs: `oc logs -n cert-manager -l app=trust-manager`

### Certificates not issuing
- Check CA certs: `oc get certificate -n cert-manager`
- Check leaf certs: `oc get certificate -n trust-manager-server-ns` and
  `oc get certificate -n trust-manager-client-ns`
- Check ClusterIssuer: `oc get clusterissuer intermediate-ca-cluster-issuer -o yaml`

### mTLS handshake failures
- Check server logs: `oc logs -n trust-manager-server-ns -l app=mtls-server`
- Verify trust bundle is mounted: `oc exec <client-pod> -n trust-manager-client-ns -- cat /etc/trust/ca-bundle.crt | head`

### Rotation timing
- The intermediate CA renews ~10 minutes after creation
- Check status: `oc get certificate intermediate-ca -n cert-manager -o yaml`
- After rotation, nginx may need a restart to pick up the new trust bundle:
  `oc rollout restart deployment/mtls-server -n trust-manager-server-ns`

## Disclaimer

This is not guaranteed to work in all environments. The `TechPreviewNoUpgrade`
FeatureGate is irreversible and not recommended for production clusters.
This demo is intended for learning and development environments only.
