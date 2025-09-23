#!/bin/bash

# Utility function for getting pod name in ns
# NOTE: only 1 pod is expected to be running in the ns
# $1: pod name to grep
# $1: pod namespace
get_pod_name() {

  while [[ $(oc get pods -n $2 | grep $1) == "" ]]; do
    sleep 1
  done
  echo $(oc get pods -n $2 --no-headers | grep $1 | awk '{ print $1 }')
}

# Utility function for inspecting pod readiness
# $1: pod name
# $2: pod namespace
await_pod_ready() {
  echo "awaiting pod $1 ready in ns $2"
  while [[ $(get_pod_status $1 $2) != "True" ]]; do
    sleep 1
  done
  echo "pod ready"
}

# Utility function for inspecting CSV readiness
# $1: namespace
await_csv_ready() {
  echo "awaiting csv ready in ns $1"
  NAME=$(get_csv_name $1)
  while [[ $(get_csv_status $NAME $1) != "Succeeded" ]]; do
    sleep 1
  done
  echo "csv ready"
}

# Helper functions
get_pod_status() {
  echo $(oc get pods $1 \
    -n $2 \
    -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}')
}

get_csv_name() {

  while [[ $(oc get csv -n $1) == "" ]]; do
    sleep 1
  done
  echo $(oc get csv -n $1 --no-headers | awk '{print $1}')
}

get_csv_status() {
  echo $(oc get csv $1 \
    -n $2 \
    -o 'jsonpath={..status.phase}')
}
