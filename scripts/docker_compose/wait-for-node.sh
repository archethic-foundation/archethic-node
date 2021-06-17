#!/usr/bin/env bash

set -e

curl="$1"
node="${curl#*//}"
node="${node%:*}"
shift
cmd="$@"
wget="wget -qO /dev/null"

until $wget "$curl" ; do
  >&2 echo "Node $node is unavailable - sleeping"
  sleep 1
done

>&2 echo "Node $node is up - executing command"
exec $cmd
