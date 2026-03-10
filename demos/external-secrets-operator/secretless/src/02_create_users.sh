#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

HTPASSWD_PATH=""

help() {
    # Display Help
    echo "This script will help to configure the role and rolebindings"
    echo "for this demo using an htpasswd file with 2 users: admin, user"
    echo
    echo "Syntax: 02_setup_users.sh [-h|n|f]"
    echo "options:"
    echo "f     Use pre-existing htpasswd file for this demo."
    echo "      MUST INCLUDE two usernames: demo_admin, demo_user"
    echo "      EXAMPLE: /path/to/my/users.htpasswd"
    echo "n     Creates new htpasswd file for this demo to use"
    echo "h     Print help message"
    echo
}

new() {
    HTPASSWD_PATH="$SCRIPT_DIR/config/users.htpasswd"
    # ensure no existing htpasswd file exists
    rm $HTPASSWD_PATH
    # create new htpasswd file
    echo "Enter password for 'demo_admin' demo_user:"
    htpasswd -cB $HTPASSWD_PATH demo_admin
    echo "Enter password for 'demo_user' user:"
    htpasswd -B $HTPASSWD_PATH demo_user
    echo "Created new htpasswd file: $HTPASSWD_PATH"
}

echo "ALERT!!"
echo "This script is used to create 2 new users via HTPASSWD"
echo "This method is NOT recommended if you are NOT using a demo/ephemeral cluster"
echo "If your cluster is configured with an OIDC such as Keycloak, you can simply create 2 users: demo_admin and demo_user"
echo "Do you still want to proceed?"
read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

# Get the options
while getopts ":hnf:" option; do
   case $option in
      h) # display Help
         help
         exit;;
      n) # new htpasswd file
         new;;
      f) # file path to htpasswd file
         HTPASSWD_PATH=$OPTARG;;
      \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done

if [[ $HTPASSWD_PATH == "" ]];
then
  echo "Please use -n option to create a new htpasswd file"
  echo "OR"
  echo "Use the -f option to pass this script an existing htpasswd file"
  exit 1
fi;

oc create secret generic demo-htpass-secret \
  --from-file=htpasswd=$HTPASSWD_PATH \
  -n openshift-config

oc patch oauth cluster \
  --type json \
  --patch-file $SCRIPT_DIR/config/oauth.yaml
