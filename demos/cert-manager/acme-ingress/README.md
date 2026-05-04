# ACME (Let's Encrypt) Demo for Ingress

This demo uses cert-manager with the ACME protocol to obtain
TLS certificates from [Let's Encrypt](https://letsencrypt.org/).
It deploys a simple `hello-openshift` application behind an
Ingress secured with a certificate issued by Let's Encrypt.

Unlike the self-signed demos in this repository, this demo
produces certificates from a real Certificate Authority. The
demo deploys a Let's Encrypt **production** Issuer by default
(for trusted certificates), or a **staging** Issuer for safe
testing.

## Prerequisites

Must have the following installed:
- `oc`
- `curl`

Additionally, the following conditions must be met:
- The OpenShift cluster must be **publicly accessible** from the
  internet (required for the HTTP-01 ACME challenge)
- A valid email address for Let's Encrypt registration
- The cluster's wildcard DNS (`*.apps.<base_domain>`) must
  resolve to the cluster's ingress controller

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ACME_EMAIL` | Yes | - | Email address for Let's Encrypt registration |
| `ACME_ISSUER` | No | `letsencrypt-production` | Issuer to use (`letsencrypt-production` or `letsencrypt-staging`) |
| `INGRESS_CLASS` | No | `openshift-default` | IngressClass name for the HTTP-01 solver |

## Steps

1. Set the required environment variable:
```sh
export ACME_EMAIL=you@example.com
```

2. Make sure to log in with your admin credentials via `oc login` command

3. Run the scripts in order from the `src` folder:
```sh
# Installs cert-manager operator
./01_install_cert_manager_operator.sh

# Creates a Let's Encrypt ACME Issuer (production by default)
./02_deploy_acme_issuers.sh

# Deploys a sample deployment, service, ingress, and certificate
# Waits for certificate issuance and verifies TLS
./03_deploy_example_application.sh

# Cleanup step. Tears down the resources created during the prior steps
./04_cleanup.sh
```

## Using Staging Certificates

By default, the demo uses the Let's Encrypt **production** environment,
which issues publicly trusted certificates. To use the staging
environment instead (useful for repeated testing without hitting
rate limits):

```sh
export ACME_ISSUER=letsencrypt-staging
```

**Note:** Staging certificates are **not** publicly trusted. The
demo will automatically use `curl -k` to skip TLS verification
when using staging.

**Warning:** Let's Encrypt production has strict
[rate limits](https://letsencrypt.org/docs/rate-limits/)
(50 certificates per registered domain per week). Use staging
for repeated testing.

## How It Works

1. cert-manager creates an ACME account with Let's Encrypt
   using the provided email address
2. When a Certificate resource is created, cert-manager
   initiates an HTTP-01 challenge
3. cert-manager creates a temporary Ingress and a solver Pod
   that serves the challenge token at
   `http://<domain>/.well-known/acme-challenge/<token>`
4. Let's Encrypt verifies the challenge by making an HTTP
   request to the domain
5. Once verified, Let's Encrypt issues the certificate
6. cert-manager stores the certificate in the specified
   Kubernetes Secret (`acme-tls`)
7. The Ingress references this Secret for TLS termination

## Troubleshooting

### Certificate stuck in "not ready" state

Check the Certificate, CertificateRequest, Order, and Challenge
resources:

```sh
oc describe certificate acme-certificate -n cert-manager-acme-ns
oc get certificaterequest -n cert-manager-acme-ns
oc get order -n cert-manager-acme-ns
oc get challenge -n cert-manager-acme-ns
```

### HTTP-01 challenge failing

- Verify the cluster is publicly accessible
- Check that the wildcard DNS resolves correctly:
  `nslookup hello-openshift-acme.apps.<base_domain>`
- Verify the solver Pod is running:
  `oc get pods -n cert-manager-acme-ns`
- Check cert-manager controller logs:
  `oc logs -n cert-manager -l app=cert-manager`

### IngressClass issues

On OpenShift versions before 4.14, the IngressClass name may
differ. Check available IngressClasses:

```sh
oc get ingressclass
```

Set the correct value via `export INGRESS_CLASS=<name>`.

## Disclaimer

This is not guaranteed to work in all environments, and is meant
to showcase an extremely simple example of how an application's
Ingress can be secured via TLS certificates issued by Let's
Encrypt through cert-manager.
