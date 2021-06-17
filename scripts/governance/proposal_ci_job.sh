#!/bin/bash

set -e

PROPOSAL_ADDRESS=$1
PROPOSAL_FILENAME=/tmp/proposal

echo "=== Test proposal ${PROPOSAL_ADDRESS}"
tee ${PROPOSAL_FILENAME}

echo "=== Create branch ${PROPOSAL_ADDRESS}"
git checkout -b "prop_${PROPOSAL_ADDRESS}"

echo "=== Apply patch ${PROPOSAL_FILENAME}"
git am ${PROPOSAL_FILENAME} --committer-date-is-author-date --no-gpg-sign

echo "=== Run CI"
mix git_hooks.run pre_push

echo "=== Create upgrade"
mix distillery.release --upgrade

echo "=== Create validator"
mix escript.build
