#!/bin/bash

set -e

PROPOSAL_ADDRESS=$1
PROPOSAL_PATCH_FILENAME=$2
PROPOSAL_DESCRIPTION=$3

echo "Create branch for the proposal ${PROPOSAL_ADDRESS}"
git checkout -b "prop_${PROPOSAL_ADDRESS}"

echo "Apply patch ${PROPOSAL_PATCH_FILENAME}"
git apply $PROPOSAL_PATCH_FILENAME
if [ $? -eq 0 ]; then
  echo "Commit"
  git add .
  git commit -m "$PROPOSAL_DESCRIPTION"
  mix git_hooks.run pre_push
else
  exit 1;
fi

