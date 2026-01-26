#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

oc apply -f $SCRIPT_DIR/config/cluster-monitoring-config.yaml
oc apply -f $SCRIPT_DIR/config/servicemonitor-cert-manager.yaml

oc new-project cert-manager-monitor-ns

BASE_DOMAIN=$(oc get dns/cluster -o=jsonpath='{.spec.baseDomain}')
APP_PREFIX=hello-openshift-ingress
HOST=${APP_PREFIX}.apps.${BASE_DOMAIN}
sed \
  -e "s|DNS_HOST|$HOST|g" \
  $SCRIPT_DIR/config/resources-to-monitor.yaml > $SCRIPT_DIR/config/tmp-resources-to-monitor.yaml

oc apply -f $SCRIPT_DIR/config/tmp-resources-to-monitor.yaml
