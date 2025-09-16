#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create new demo project
oc new-project cert-manager-demo-ns
oc project cert-manager-demo-ns

# Deploy cert-manager Issuer and Certificates
oc apply -f $SCRIPT_DIR/config/cert_manager_crds.yaml

# Verify server certificate against CA
openssl verify -CAfile \
  <(oc get secret -n cert-manager-demo-ns test-ca-secret -o jsonpath='{.data.ca\.crt}' | base64 -d) \
  <(oc get secret -n cert-manager-demo-ns test-server-tls -o jsonpath='{.data.ca\.crt}' | base64 -d)

# Run simple test server via OpenSSL
echo Hello World! > tmp_test.txt
openssl s_server \
  -cert <(oc get secret -n cert-manager-demo-ns test-server-tls -o jsonpath='{.data.tls\.crt}' | base64 -d) \
  -key <(oc get secret -n cert-manager-demo-ns test-server-tls -o jsonpath='{.data.tls\.key}' | base64 -d) \
  -CAfile <(oc get secret -n cert-manager-demo-ns test-server-tls -o jsonpath='{.data.ca\.crt}' | base64 -d) \
  -WWW -port 12345  \
  -verify_return_error -Verify 1 &
SERVER_PID=$!

echo -e "GET /tmp_test.txt HTTP/1.1\r\n\r\n" | \
  openssl s_client \
    -cert <(oc get secret -n cert-manager-demo-ns test-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d) \
    -key <(oc get secret -n cert-manager-demo-ns test-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d) \
    -CAfile <(oc get secret -n cert-manager-demo-ns test-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d) \
    -connect localhost:12345 -quiet

kill -9 $SERVER_PID
rm tmp_test.txt
