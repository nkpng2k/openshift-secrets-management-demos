#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

oc new-project eso-demo-ns
oc project eso-demo-ns

oc create serviceaccount -n eso-demo-ns eso-demo-sa
oc create clusterrolebinding eso-demo-crb \
  --clusterrole=system:auth-delegator \
  --serviceaccount=eso-demo-ns:eso-demo-sa
