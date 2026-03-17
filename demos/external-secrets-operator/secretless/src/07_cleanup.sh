#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="secretless/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Cleanup demo namespaces
oc delete project demo-namespace-user
oc delete project demo-namespace-admin

# ALERT ABOUT CREATED DEMO USERS
oc delete secret demo-htpass-secret -n openshift-config
oc delete clusterrole demo-admin-eso-limited-role
echo "ALERT!!!"
echo "ALERT!!!"
echo "There is no programatic way to reset the changes to the oauth providers cleanly"
echo "IF you used script ./02_create_users.sh"
echo "Make sure to revert any changes either in the OpenShift console of via the CLI"
echo "Current OAuth configuration:"
oc describe oauth cluster

# Run generalized install scripts
/bin/bash $OPERATOR_DIR/cleanup.sh
/bin/bash $OPERATOR_DIR/cleanup_vault.sh
