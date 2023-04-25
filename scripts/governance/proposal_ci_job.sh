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

echo "=== git commit"
git commit -m "${PROPOSAL_DESCRIPTION}"

echo "=== Run CI START ==="

echo "=== Run CI -- Part 1 -- clean "
mix clean

echo "=== Run CI -- Part 2 -- format"
mix format --check-formatted

echo "=== Run CI -- 3 -- compile"
mix compile --warnings-as-errors

echo "=== Run CI -- 4 -- credo"
mix credo

echo "=== Run CI -- 5 -- sobelow"
mix sobelow

echo "=== Run CI -- 6 -- knigge"
mix knigge.verify

echo "=== Run CI -- 7 -- test"
MIX_ENV=test mix test --trace 

echo "=== Run CI -- 8 -- dialyzer"
mix dialyzer

echo "=== Run CI -- 9 -- updates"
mix check.updates

echo "=== Run CI DONE ==="

echo "=== Create upgrade release"
MIX_ENV=prod mix distillery.release --upgrade
