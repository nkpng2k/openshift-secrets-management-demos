#!/bin/bash

# source variables and util functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

HTPASSWD_PATH=""

new() {
    HTPASSWD_PATH="$SCRIPT_DIR/config/users.htpasswd"
    # ensure no existing htpasswd file exists
    rm $HTPASSWD_PATH
    # create new htpasswd file
    echo "Enter password for 'admin' user:"
    htpasswd -cB $HTPASSWD_PATH admin
    echo "Enter password for 'user' user:"
    htpasswd -B $HTPASSWD_PATH user
    echo "Created new htpasswd file: $HTPASSWD_PATH"
}

# Get the options
while getopts ":hnf:" option; do
   case $option in
      h) # display Help
         echo "help"
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


