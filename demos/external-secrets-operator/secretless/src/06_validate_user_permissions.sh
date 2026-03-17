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

# User should only be able to list secrets. NO other permissions
# User should NOT be able to list secrets in admin namespace
can_i "list" "secrets" $USER_NS $USER_USER $YES

can_i "list" "secrets" $ADMIN_NS $USER_USER $NO
can_i "get" "secrets" $ADMIN_NS $USER_USER $NO
can_i "get" "secrets" $USER_NS $USER_USER $NO
can_i "list" "externalsecrets" $ADMIN_NS $USER_USER $NO
can_i "list" "externalsecrets" $USER_NS $USER_USER $NO
can_i "get" "externalsecrets" $ADMIN_NS $USER_USER $NO
can_i "get" "externalsecrets" $USER_NS $USER_USER $NO
can_i "impersonate" "serviceaccounts" $ADMIN_NS $USER_USER $NO
can_i "impersonate" "serviceaccounts" $USER_NS $USER_USER $NO

# # can-i
# oc whoami --as demo_user
# oc auth can-i list secrets -n demo-namespace-user --as demo_user
# oc auth can-i list secrets -n demo-namespace-admin --as demo_user
# oc auth can-i list externalsecrets -n demo-namespace-admin --as demo_user
# oc auth can-i list externalsecrets -n demo-namespace-user --as demo_user

# # Attempt to list / get / describe
# oc get projects --as demo_user
# oc get secrets -n demo-namespace-user --as demo_user
# oc get externalsecrets -n demo-namespace-user --as demo_user