# Trust-Manager mTLS Demo for OpenShift

This demo uses cert-manager and trust-manager to create a certificate
chain (root CA → intermediate CA → server/client leaf certificates),
distribute trust material across namespaces via a trust-manager Bundle,
and deploy two applications communicating over mTLS.

The demo validates the full chain of trust and demonstrates that
trust-manager automatically updates the trust bundle when the
intermediate CA certificate is renewed by cert-manager.

trust-manager is a Technology Preview component of the Red Hat
cert-manager operator for OpenShift 4.21 (cert-manager 1.19).

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
# Installs the cert-manager operator
./01_install_cert_manager_operator.sh

# Creates the certificate chain: root CA -> intermediate CA -> server/client leaf certs
./02_deploy_certificate_chain.sh

# Creates a trust-manager Bundle and distributes CA trust material across namespaces
./03_deploy_trust_bundle.sh

# Deploys an mTLS server (nginx) and client, validates basic connectivity
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
1. A self-signed Issuer bootstraps a Root CA certificate
2. The Root CA issues an Intermediate CA certificate (short-lived: 10m duration)
3. The Intermediate CA issues two leaf certificates:
   - A **server** certificate with `server auth` usage for the nginx mTLS server
   - A **client** certificate with `client auth` usage for the client application

### Trust Distribution
1. A trust-manager `Bundle` resource is created, sourcing CA certificates from:
   - The intermediate CA secret
   - The root CA secret
   - The OpenShift cluster's default CAs (`useDefaultCAs: true`)
2. trust-manager distributes these as a ConfigMap (`demo-trust-bundle`) to
   all namespaces with the label `trust-manager-demo: "true"`
3. Both the server and client pods mount this ConfigMap for TLS trust validation

### mTLS Communication
1. The **server** (nginx) is configured with `ssl_verify_client on`, requiring
   clients to present a valid certificate signed by a trusted CA
2. The **client** pod runs a validation script that connects to the server
   using its client certificate, client key, and the trust bundle as the CA
3. The trust bundle enables both sides: the client trusts the server's
   certificate, and the server trusts the client's certificate

### Automatic Rotation
1. The intermediate CA has a short duration (5m) with early renewal (2m before expiry)
2. When cert-manager renews the intermediate CA, the secret is updated with new certificate data
3. trust-manager detects the secret change and automatically updates the
   trust bundle ConfigMap in all target namespaces
4. Pods with the ConfigMap volume receive the update via kubelet sync (~60 seconds)

## Troubleshooting

### trust-manager pod not appearing
- Verify FeatureGate is set: `oc get featuregate cluster -o jsonpath='{.spec.featureSet}'`
- Check operator logs: `oc logs -n cert-manager-operator -l name=cert-manager-operator`
- Check for trust-manager pods: `oc get pods -n cert-manager | grep trust-manager`

### Bundle not distributing ConfigMaps
- Check Bundle status: `oc get bundle demo-trust-bundle -o yaml`
- Verify namespace labels: `oc get ns -l trust-manager-demo=true`
- Check trust-manager logs: `oc logs -n cert-manager -l app=trust-manager`

### mTLS handshake failures
- Verify certificates are Ready: `oc get certificate -n trust-manager-demo-ns`
- Check server logs: `oc logs -n trust-manager-demo-ns -l app=mtls-server`
- Verify trust bundle is mounted: `oc exec <client-pod> -- cat /etc/trust/ca-bundle.crt | head`

### Rotation timing
- The intermediate CA renews ~3 minutes after creation (renewBefore: 2m of 5m duration)
- Check certificate status: `oc get certificate intermediate-ca -n trust-manager-demo-ns -o yaml`
- After rotation, nginx may need a restart to pick up the new server cert:
  `oc rollout restart deployment/mtls-server -n trust-manager-demo-ns`

## Disclaimer

This is not guaranteed to work in all environments. The `TechPreviewNoUpgrade`
FeatureGate is irreversible and not recommended for production clusters.
This demo is intended for learning and development environments only.
