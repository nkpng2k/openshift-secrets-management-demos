# Zero Trust Workload Identity with ESO

This demo shows how to use the
[Red Hat Zero Trust Workload Identity Manager](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/security_and_compliance/zero-trust-workload-identity-manager)
(ZTWIM, based on SPIFFE/SPIRE) as the authentication layer for
[External Secrets Operator](https://external-secrets.io/) (ESO) ClusterSecretStores
backed by HashiCorp Vault.

Workloads receive cryptographic identities through platform attestation rather
than pre-shared credentials, solving the "secret zero" problem.

## Architecture

The ESO controller pod runs with two sidecars injected via Helm `extraContainers`:

- **spiffe-helper**: Fetches JWT SVIDs from the SPIRE Workload API and writes
  them to a shared volume.
- **jwt-server**: A busybox httpd serving the JWT token file on localhost:8080.

An ESO Webhook Generator reads the JWT from localhost and produces a K8s Secret
(`spiffe-jwt`). ClusterSecretStores reference this Secret for Vault JWT
authentication. Adding a new team requires only a Vault role, a
ClusterSecretStore, and an ExternalSecret — no new pods or sync infrastructure.

```
                    ESO Controller Pod
                    +-------------------------------------------+
SPIRE Agent         |  spiffe-helper -> jwt file -> httpd:8080  |
+-----------+  CSI  |         |                      |          |
| Workload  +------>|  Workload API socket           |          |
| API       |       |                                |          |
+-----------+       |  Webhook Generator -> localhost:8080      |
                    |         |                                 |
                    |  ExternalSecret (generatorRef)            |
                    |         | creates K8s Secret "spiffe-jwt" |
                    |         v                                 |
                    |  ClusterSecretStore (jwt auth)            |
                    |         | refs Secret "spiffe-jwt"        |
                    |         v                                 |
                    |  ExternalSecret -> Vault -> team-secret   |
                    +-------------------------------------------+

Vault (dev mode, HTTP)
+-- JWT auth validates via SPIRE OIDC Discovery Provider
+-- Role "team-a-role" -> policy: read kv/team-a/*
+-- Role "team-b-role" -> policy: read kv/team-b/*
```

Identity isolation is enforced by Vault: the ESO controller authenticates with
a single SPIFFE identity, but each ClusterSecretStore maps to a distinct Vault
role and policy. `team-a` can only read `kv/team-a/*` and `team-b` can only
read `kv/team-b/*`.

## Prerequisites

Must have the following installed:
- `oc`
- `helm`

Must have admin credentials for an OpenShift 4.18+ cluster and be logged in
via: `oc login ...`

The ZTWIM operator must be available in the operator catalog
(`redhat-operators`).

## Steps

1. Edit `src/config/variables.sh` to configure trust domain, namespaces,
   and image versions as needed.
2. Run the scripts in order from the `src` folder:

```sh
# Install ZTWIM operator, Vault (dev mode), and create team namespaces
./01_install.sh

# Configure ZTWIM: deploy SPIRE components, create ClusterSPIFFEID for ESO
./02_configure_ztwim.sh

# Install ESO via Helm with SPIFFE sidecars, deploy Webhook Generator
./03_install_eso.sh

# Configure Vault JWT auth with SPIRE OIDC, create per-team roles/policies
./04_configure_vault.sh

# Deploy ClusterSecretStores and ExternalSecrets per team namespace
./05_deploy_demo.sh

# Validate that secrets synced correctly and identity isolation works
./06_validate.sh

# Cleanup: tear down all resources
./07_cleanup.sh
```

## Expected Output

After running `06_validate.sh`, you should see:

```
--- ClusterSecretStores ---
vault-team-a: Ready = True
vault-team-b: Ready = True

--- Namespace: team-a ---
ExternalSecret: SecretSynced = True
Synced secret: username=team-a-user password=s3cret-team-a-456

--- Namespace: team-b ---
ExternalSecret: SecretSynced = True
Synced secret: username=team-b-user password=s3cret-team-b-789

=== Identity Isolation Check ===
SUCCESS: Teams have different secrets, identity isolation confirmed.

=== ALL VALIDATIONS PASSED ===
```

## Scaling

Adding a new team requires only:

1. A Vault role + policy (`vault write auth/jwt/role/team-c-role ...`)
2. A ClusterSecretStore for team-c
3. An ExternalSecret in the team-c namespace

No new pods, no new sync infrastructure, no image builds.

## Troubleshooting

- **spiffe-jwt Secret not appearing**: Check spiffe-helper and jwt-server logs:
  `oc logs -n external-secrets deploy/external-secrets -c spiffe-helper`
  `oc logs -n external-secrets deploy/external-secrets -c jwt-server`
- **ClusterSecretStore not ready**: Check if the spiffe-jwt Secret exists:
  `oc get secret spiffe-jwt -n external-secrets -o yaml`
- **Vault JWT validation fails**: Verify the OIDC Discovery Provider is
  accessible from the Vault pod:
  `oc exec vault-0 -n hashicorp-vault -- curl -sk https://<oidc-svc>.<spire-ns>.svc/.well-known/openid-configuration`
- **ESO controller not starting**: Check if the SPIFFE CSI driver is running:
  `oc get pods -n spire-system -l app=spiffe-csi-driver`

## Disclaimer

This is not guaranteed to work in all environments, and is meant to showcase
how ZTWIM can provide zero-trust workload identity for ESO ClusterSecretStores.
The ZTWIM CRD API versions and field names may vary across OpenShift versions.
