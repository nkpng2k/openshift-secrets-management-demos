#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEMO_SRC_DIR="policies/src"
OPERATOR_DIR=$(sed "s|$DEMO_SRC_DIR|operator|g" <<< "$SCRIPT_DIR")

# Run generalized install scripts
/bin/bash $OPERATOR_DIR/cleanup.sh
/bin/bash $OPERATOR_DIR/cleanup_vault.sh
