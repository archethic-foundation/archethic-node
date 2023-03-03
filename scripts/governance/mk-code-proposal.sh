@@ -1,35 +1,38 @@ 
#!/bin/bash

# Assuming that the current branch is a feature branch and the most recent
# version of the source code is on the default_main_branch branch, 
# this script creates code-proposal.patch file.

default_main_branch="fixing_governance_ci"
status=$(git status --porcelain)

if [ -n "$status" ]; then
  echo "Commit your changes or stash them before running this script"
  exit 1
fi

feature_branch=$(git rev-parse --abbrev-ref HEAD)
feature_log=$(git log --format="  * %B" ${default_main_branch}..)
summary="📦 ${feature_branch}\n\n${feature_log}"

cleanup() { git checkout $feature_branch; }

trap cleanup ERR

set -e

git checkout ${default_main_branch}

git merge --squash $feature_branch

if (echo -e "$summary" |\
  git commit --author="archethic <dev@archethic.net>" --no-gpg-sign --edit -F-)
then
  git format-patch --stdout ${default_main_branch}^ > code-proposal.patch
  git reset --hard ${default_main_branch}^
fi

git checkout $feature_branch