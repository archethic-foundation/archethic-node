#!/bin/bash

# Assuming that the current branch is a feature branch and the most recent
# version of the source code is on the master branch, this script creates
# code-proposal.patch file.

status=$(git status --porcelain)

if [ -n "$status" ]; then
  echo "Commit your changes or stash them before running this script"
  exit 1
fi

feature_branch=$(git rev-parse --abbrev-ref HEAD)
feature_log=$(git log --format="  * %B" master..)
summary="📦 ${feature_branch}\n\n${feature_log}"

set -e

git checkout master

git merge --squash $feature_branch

if (echo -e "$summary" |\
  git commit --author="uniris <uniris@uniris.io>" --no-gpg-sign --edit -F-)
then
  git format-patch --stdout master^ > code-proposal.patch
  git reset --hard master^
fi

git checkout $feature_branch
