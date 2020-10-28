#!/bin/bash

BLUE='\033[1;34m'

usage() {
  echo "Usage:"
  echo ""
  echo " Install Uniris node dependencies and application"
  echo ""
  echo "  " install.sh [-d  dir] " Specify the installation dir for the application"
  echo "  " install.sh -h "       Print the help usage"
  echo ""
}

while getopts d:h option
do
    case "${option}"
    in
        d) INSTALL_DIR=${OPTARG};;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

echo -e "${BLUE}"

cat << "EOF"
 _   _       _      _                       _        _           _        _ _
| | | |     (_)    (_)                     | |      (_)         | |      | | |
| | | |_ __  _ _ __ _ ___   _ __   ___   __| | ___   _ _ __  ___| |_ __ _| | | ___ _ __
| | | | '_ \| | '__| / __| | '_ \ / _ \ / _` |/ _ \ | | '_ \/ __| __/ _` | | |/ _ \ '__|
| |_| | | | | | |  | \__ \ | | | | (_) | (_| |  __/ | | | | \__ \ || (_| | | |  __/ |
 \___/|_| |_|_|_|  |_|___/ |_| |_|\___/ \__,_|\___| |_|_| |_|___/\__\__,_|_|_|\___|_|
EOF

sh ./scripts/install_system_deps.sh
sh ./scripts/release.sh -d INSTALL_DIR