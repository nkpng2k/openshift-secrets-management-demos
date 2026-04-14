#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/secretless/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Validate demo_admin user
echo "Validating permissions for demo_admin user"
USER_USER="demo_user"
ADMIN_NS="demo-namespace-admin"
USER_NS="demo-namespace-user"

# can-i
YES="yes"
NO="no"

# User should NOT have any access to secrets. Can list events for diagnostics.
can_i "list" "secrets" $USER_NS $USER_USER $NO
can_i "list" "secrets" $ADMIN_NS $USER_USER $NO
can_i "list" "events" $USER_NS $USER_USER $YES
can_i "get" "secrets" $ADMIN_NS $USER_USER $NO
can_i "get" "secrets" $USER_NS $USER_USER $NO
can_i "list" "externalsecrets" $ADMIN_NS $USER_USER $NO
can_i "list" "externalsecrets" $USER_NS $USER_USER $NO
can_i "get" "externalsecrets" $ADMIN_NS $USER_USER $NO
can_i "get" "externalsecrets" $USER_NS $USER_USER $NO
can_i "impersonate" "serviceaccounts" $ADMIN_NS $USER_USER $NO
can_i "impersonate" "serviceaccounts" $USER_NS $USER_USER $NO

# Functional test to validate demo_user
echo ""
echo ""
echo "Validating that admin user can perform above tested functions"
echo "YOU MUST VALIDATE THESE VISUALLY"
echo ""
echo "$USER_USER CANNOT list secrets, should see forbidden error"
oc get secrets -n $USER_NS --as $USER_USER
oc get secrets -n $ADMIN_NS --as $USER_USER
echo ""
echo "$USER_USER can list events, should see event information"
oc get events -n $USER_NS --as $USER_USER
echo ""
echo "=== EVENTS DEBUGGING DEMO ==="
echo "Events allow users to diagnose pod issues WITHOUT accessing secrets."
echo ""
echo "demo-app-success pod events (should show successful scheduling and mount):"
oc get events -n $USER_NS --as $USER_USER --field-selector involvedObject.name=demo-app-success
echo ""
echo "demo-app-failure pod events (should show mount failure for non-existent secret):"
oc get events -n $USER_NS --as $USER_USER --field-selector involvedObject.name=demo-app-failure
echo ""
echo "$USER_USER CANNOT describe secrets, should see forbidden error"
oc get secret vault-secret-example -n $USER_NS --as $USER_USER
oc get secret vault-special-secret-example -n $ADMIN_NS --as $USER_USER
echo ""
echo "$USER_USER CANNOT list externalsecrets, should see forbidden error"
oc get externalsecrets -n $ADMIN_NS --as $USER_USER
oc get externalsecrets -n $USER_NS --as $USER_USER
echo ""
echo "$USER_USER CANNOT describe externalsecrets, should see forbidden error"
oc describe externalsecrets vault-external-secret-admin -n $ADMIN_NS --as $USER_USER
oc describe externalsecrets vault-external-secret-user -n $USER_NS --as $USER_USER
