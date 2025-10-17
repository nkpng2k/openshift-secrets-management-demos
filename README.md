# OpenShift Secrets Management Demos

This repository is dedicated to demos and quick-starts associated
with using secrets management tools in OpenShift. The goal is to
provide clear guides on how to:
1. Deploy the secrets management tool.
2. Configure the tool such that an application can obtain secrets
from it.
3. Deploy a simple example application that can consume the secrets
provided by the secrets management tool. 

We do not promise that any of the demos will work in all environments,
but aim to provide ample instruction regarding the installation
process and usage as to minimize confusion.

### Prerequisites

This repository is not expected to contain instructions on how to
deploy OpenShift nor is it expected to contain instructions on how
to deploy the external secrets management repository such as
CyberArk Conjur or HashiCorp Vault. The following list 
of prerequisites is not comprehensive:
* A running OpenShift cluster
* An admin and user level set of credentials for the OpenShift cluster
* A running instance of your preferred secrets management repository

### Demos

If you want to run demos for secrets management on OpenShift, you can
look into the [demos](./demos/) directory. This contains the necessary
scripts to run a demo.

The scripts are somewhat modular:
- Use the `demos/<operator name>/operator` directory to see the generic
install steps.
- Use the `demos/<operator name>/<feature name>` directory to see the
appropriately named demo steps. Most of these demos use the install
scripts from their respective `operator` directories.

### QuickStarts

The [console/quickstart](./console/quick-start/) directory contains
OpenShift Console QuickStarts which can be installed on an OpenShift
cluster.

# Contribution

In order to ensure the quality of demos contributed to this
repository. Any contribution should include:

- [ ] A relatively well written README file
- [ ] A commented deployment script
- [ ] A commented dependencies file (ex. requirements.txt)
- [ ] All necessary `.yaml` files required for deployment
of Kubernetes resources.

Any contributions must be made via Pull Request.
