#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add RBAC permissions for router to read referenced secrets
oc create role secret-reader \
  --verb=get,list,watch \
  --resource=secrets \
  --resource-name=test-server-tls

oc create rolebinding secret-reader-binding \
  --role=secret-reader \
  --serviceaccount=openshift-ingress:router

# Get OpenShift DNS name
BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-route
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}

sed \
  -e "s|DNS_HOST|$HOST|g" \
  $SCRIPT_DIR/config/cert_manager_example.yaml > $SCRIPT_DIR/config/tmp_cert_manager_example.yaml
oc apply -f $SCRIPT_DIR/config/tmp_cert_manager_example.yaml

# Wait a bit for the deployment to be ready
wait_spinner 15

# Run test with curl
curl --cacert <(oc get secret -n cert-manager-demo-ns test-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d) \
  -v https://$HOST

# Sample test without --cacert should fail
# curl -v https://$HOST
