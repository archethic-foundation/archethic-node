#!/bin/bash

set -e

PROPOSAL_ADDRESS=$1
PROPOSAL_DESCRIPTION=$2
PROPOSAL_FILENAME=./proposal.diff

echo "=== Test proposal ${PROPOSAL_ADDRESS}"
tee ${PROPOSAL_FILENAME}

echo "=== Create branch ${PROPOSAL_ADDRESS}"
git checkout -b "prop_${PROPOSAL_ADDRESS}"

echo "=== Apply patch ${PROPOSAL_FILENAME}"
git apply ${PROPOSAL_FILENAME} 

echo "=== git add files"
git add --all

echo "=== git commit "
git commit -m "${PROPOSAL_DESCRIPTION}"

echo "=== Run CI"
mix git_hooks.run pre_push

echo "=== Create upgrade"
mix distillery.release --upgrade
