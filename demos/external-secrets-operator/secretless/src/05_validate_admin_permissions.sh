#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="external-secrets-operator/secretless/src"
UTILS_DIR=$(sed "s|$DEMO_SRC_DIR|utils|g" <<< "$SCRIPT_DIR")
source $UTILS_DIR/ocp.sh

# Validate demo_admin user
echo "Validating permissions for demo_admin user"
ADMIN_USER="demo_admin"
ADMIN_NS="demo-namespace-admin"
USER_NS="demo-namespace-user"

# can-i
YES="yes"
NO="no"

# Admin should be able to list secrets and get externalsecrets but NOT get secrets
# This should be true in both demo namespaces
can_i "list" "secrets" $ADMIN_NS $ADMIN_USER $YES
can_i "list" "secrets" $USER_NS $ADMIN_USER $YES
can_i "list" "externalsecrets" $ADMIN_NS $ADMIN_USER $YES
can_i "list" "externalsecrets" $USER_NS $ADMIN_USER $YES
can_i "get" "externalsecrets" $ADMIN_NS $ADMIN_USER $YES
can_i "get" "externalsecrets" $USER_NS $ADMIN_USER $YES

can_i "get" "secrets" $ADMIN_NS $ADMIN_USER $NO
can_i "get" "secrets" $USER_NS $ADMIN_USER $NO
can_i "impersonate" "serviceaccounts" $ADMIN_NS $ADMIN_USER $NO
can_i "impersonate" "serviceaccounts" $USER_NS $ADMIN_USER $NO

# Functional test to validate demo_admin
echo ""
echo ""
echo "Validating that admin user can perform above tested functions"
echo "YOU MUST VALIDATE THESE VISUALLY"
echo ""
echo "$ADMIN_USER can list secrets, should see list of secrets"
oc get secrets -n $ADMIN_NS --as $ADMIN_USER
oc get secrets -n $USER_NS --as $ADMIN_USER
echo ""
echo "$ADMIN_USER CANNOT get secrets, should see forbidden error" 
oc get secret vault-secret-example -n $USER_NS --as $ADMIN_USER
oc get secret vault-special-secret-example -n $USER_NS --as $ADMIN_USER
echo ""
echo "$ADMIN_USER can list externalsecrets, should see list of externalsecrets"
oc get externalsecrets -n $ADMIN_NS --as $ADMIN_USER
oc get externalsecrets -n $USER_NS --as $ADMIN_USER
echo ""
echo "$ADMIN_USER can get externalsecrets, should see externalsecret details (head 5)"
oc describe externalsecrets vault-external-secret-admin -n $ADMIN_NS --as $ADMIN_USER | head -n 5
oc describe externalsecrets vault-external-secret-user -n $USER_NS --as $ADMIN_USER | head -n 5
