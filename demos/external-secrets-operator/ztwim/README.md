# Zero Trust Workload Identity with ESO

This demo shows how to use the
[Red Hat Zero Trust Workload Identity Manager](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/security_and_compliance/zero-trust-workload-identity-manager)
(ZTWIM, based on SPIFFE/SPIRE) as the authentication layer for
[External Secrets Operator](https://external-secrets.io/) (ESO)
ClusterSecretStores and namespace-scoped SecretStores backed by HashiCorp Vault.

Workloads receive cryptographic identities through platform attestation rather
than pre-shared credentials, solving the "secret zero" problem.

## Architecture

The ESO controller pod runs with a **jwt-fetcher** sidecar injected via Helm
`extraContainers`. This sidecar uses the Red Hat SPIRE agent image and calls
`spire-agent api fetch jwt` with the `-spiffeID` flag to fetch per-team JWT
SVIDs. It also serves the JWT files via Python HTTP server on port 8888.

The ESO controller pod is registered with multiple SPIFFE identities via
separate ClusterSPIFFEID resources — one default identity for
ClusterSecretStores, plus one per team for namespace-scoped SecretStores.

```
                    ESO Controller Pod
                    +-----------------------------------------------+
SPIRE Agent         |  jwt-fetcher sidecar (spire-agent image)      |
+-----------+  CSI  |    spire-agent api fetch jwt                  |
| Workload  +------>|      -spiffeID default -> jwt-svid.json       |
| API       |       |      -spiffeID team-a  -> team-a.json         |
+-----------+       |      -spiffeID team-b  -> team-b.json         |
                    |    python3 http.server :8888                   |
                    +-----------------------------------------------+
                           |                           |
              ClusterSecretStore path       SecretStore path
              (shared ESO identity)         (per-team identity)
                           |                           |
                    +------+------+             +------+------+
                    |             |             |             |
               vault-team-a vault-team-b  vault-local   vault-local
               (team-a-role) (team-b-role) (team-a ns)  (team-b ns)
                    |             |        team-a-       team-b-
                    v             v        local-role    local-role
               team-secret   team-secret       |             |
               (team-a ns)   (team-b ns)       v             v
                                          team-secret-  team-secret-
                                          local         local

Vault (dev mode, HTTP)
+-- JWT auth validates via SPIRE OIDC Discovery Provider (route URL)
+-- ClusterSecretStore roles bound to: spiffe://<domain>/ns/<eso-ns>/sa/<eso-sa>
+-- SecretStore roles bound to: spiffe://<domain>/eso/team-a, .../eso/team-b
```

### Identity isolation

**ClusterSecretStores** use the ESO controller's default SPIFFE identity.
Isolation is enforced at the Vault policy level — each role grants access
only to the team's KV path.

**Namespace-scoped SecretStores** use per-team SPIFFE identities. Each team's
Vault role has a `bound_subject` matching only that team's SPIFFE ID. A team
cannot authenticate with another team's role, even if they have access to the
JWT — the `sub` claim in the token won't match. This provides cryptographic
identity isolation.

### No custom images

The demo uses only upstream/vendor images:
- ESO upstream Helm chart
- Red Hat SPIRE agent image (from ZTWIM operator)
- HashiCorp Vault (UBI)

## Prerequisites

Must have the following installed:
- `oc`
- `helm`

Must have admin credentials for an OpenShift 4.21+ cluster and be logged in
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

# Install ESO via Helm with jwt-fetcher sidecar, deploy Webhook Generator
./03_install_eso.sh

# Configure Vault JWT auth with SPIRE OIDC, create per-team roles/policies
./04_configure_vault.sh

# Deploy ClusterSecretStores, SecretStores, and ExternalSecrets per team
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

--- Namespace: team-a (ClusterSecretStore) ---
ExternalSecret: SecretSynced = True
Synced secret: username=team-a-user password=s3cret-team-a-456

--- Namespace: team-b (ClusterSecretStore) ---
ExternalSecret: SecretSynced = True
Synced secret: username=team-b-user password=s3cret-team-b-789

--- SecretStores (namespace-scoped) ---
vault-local (team-a): Ready = True
vault-local (team-b): Ready = True

--- Namespace: team-a (SecretStore) ---
ExternalSecret: SecretSynced = True
Synced secret: username=team-a-user password=s3cret-team-a-456

--- Namespace: team-b (SecretStore) ---
ExternalSecret: SecretSynced = True
Synced secret: username=team-b-user password=s3cret-team-b-789

=== Identity Isolation Check ===
SUCCESS: ClusterSecretStore - teams have different secrets.
SUCCESS: SecretStore - teams have different secrets.
SUCCESS: ClusterSecretStore and SecretStore secrets match for each team.

=== ALL VALIDATIONS PASSED ===
```

## Scaling

Adding a new team requires:

1. A ClusterSPIFFEID for the team's SPIFFE identity on the ESO controller pod
2. An entry in the `jwt-fetch-config` ConfigMap (and ESO pod restart)
3. A Vault role + policy (both cluster-scoped and local roles)
4. A ClusterSecretStore and/or namespace-scoped SecretStore
5. ExternalSecrets in the team namespace

No new pods, no new sync infrastructure, no image builds.

## Troubleshooting

- **spiffe-jwt Secret not appearing**: Check jwt-fetcher logs:
  `oc logs -n external-secrets deploy/external-secrets -c jwt-fetcher`
- **ClusterSecretStore not ready**: Check if the spiffe-jwt Secret exists:
  `oc get secret spiffe-jwt -n external-secrets`
- **SecretStore not ready**: Check if the team-jwt Secret exists:
  `oc get secret team-jwt -n <team-namespace>`
- **Vault JWT validation fails**: Verify the OIDC Discovery Provider route is
  reachable from the Vault pod:
  `oc exec vault-0 -n hashicorp-vault -- curl -s https://<oidc-route>/.well-known/openid-configuration`
- **ESO controller not starting**: Check if the SPIFFE CSI driver is running:
  `oc get pods -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spiffe-csi-driver`
- **Per-team JWT not fetched**: Verify the ClusterSPIFFEID exists and the SPIRE
  controller manager has processed it:
  `oc get clusterspiffeid`

## Disclaimer

This is not guaranteed to work in all environments, and is meant to showcase
how ZTWIM can provide zero-trust workload identity for ESO SecretStores.
The ZTWIM CRD API versions and field names may vary across OpenShift versions.
