#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

oc new-project eso-demo-ns
oc project eso-demo-ns

oc create serviceaccount -n eso-demo-ns eso-demo-sa

IP_ADDRESS=$(oc get svc vault -n hashicorp-vault -o 'jsonpath={..spec.clusterIP}')

sed \
  -e "s|VAULT_SVC_CLUSTER_IP|$IP_ADDRESS|g" \
  $SCRIPT_DIR/config/eso_resources.yaml > $SCRIPT_DIR/config/tmp_eso_resources.yaml
oc apply -f $SCRIPT_DIR/config/tmp_eso_resources.yaml

echo $(oc get secret -n eso-demo-ns | grep vault)
B64STRING=$(oc get secret vault-secret-example -n eso-demo-ns -o 'jsonpath={..data.password}')
echo $(base64 -d <<< $B64STRING)

oc apply -f $SCRIPT_DIR/config/eso_pod_example.yaml

# Wait a bit and then validate secret is in ENV and mounted
ENV_SECRET=$(oc exec -it -n eso-demo-ns eso-demo -- env | grep DEMO_PWD)
MOUNTED_SECRET=$(oc exec -it -n eso-demo-ns eso-demo -- cat /mnt/demo-vol/password)
echo "The secret mounted into the pod is: $MOUNTED_SECRET"
echo "The secret env var in the pod is: $ENV_SECRET"

if [[ $MOUNTED_SECRET == "demo-secret-password-123" ]]; then
  echo "SUCCESS! Mounted secret is the same as the expected secret"
else
  echo "FAIL... incorrect secret"
  echo "should have been: demo-secret-password-123"
fi
