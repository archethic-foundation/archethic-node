#!/usr/bin/env bash

set -e

cmd="$1"
shift

until $cmd;  do
  >&2 echo "Waiting..."
  sleep 1
done

>&2 echo "Executing command"
exec "$@"
