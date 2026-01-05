#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="monitor/src"
INGRESS_DIR=$(sed "s|$DEMO_SRC_DIR|self-signed-ingress|g" <<< "$SCRIPT_DIR")
ROUTES_DIR=$(sed "s|$DEMO_SRC_DIR|self-signed-route|g" <<< "$SCRIPT_DIR")

/bin/bash $INGRESS_DIR/src/02_deploy_cert_manager_crds.sh
/bin/bash $INGRESS_DIR/src/03_deploy_example_application.sh
/bin/bash $ROUTES_DIR/src/02_deploy_cert_manager_crds.sh
/bin/bash $ROUTES_DIR/src/03_deploy_example_application.sh
