#!/bin/bash

NC='\033[0m'
CYAN='\033[1;36m'

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

[[ $UID == 0 ]] || { echo "This script must be run as root."; exit 1;}




