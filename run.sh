#!/bin/bash

INSTALL_DIR="/opt/uniris_node" 
P2P_PORT=3002

# Colors
RED='\033[0;31m'
NC='\033[0m'
BLUE='\033[1;34m'

usage() {
  echo "Usage: "
  echo ""
  echo " Script to run the Uniris node"
  echo ""
  echo "  " run.sh [-d  dir] " Specify the installation dir"
  echo "  " run.sh [-k  key_file] " Specify the SSL key for HTTPS connexions"
  echo "  " run.sh [-c  cert_file] " Specify the SSL certificate for HTTPS connexions"
  echo "  " run.sh [-p  port] " Specify the P2P port"
  echo "  " run.sh -h "       Print the help usage"
  echo ""
}

while getopts d:k:c: option 
do 
    case "${option}" 
    in 
        d) INSTALL_DIR=${OPTARG};; 
        k) SSL_KEY_PATH=${OPTARG};; 
        c) SSL_CERT_PATH=${OPTARG};; 
        p) P2P_PORT=${OPTARG};;
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

if [[ "$SSL_KEY_PATH" == "" || "$SSL_CERT_PATH" == "" ]]
then
    echo "Missing SSL key/cert file"
    usage
    exit 1
fi

echo -e "${BLUE}"
cat << "EOF"                                                                                                                                                         
 _   _       _      _                       _                
| | | |     (_)    (_)                     | |     
| | | |_ __  _ _ __ _ ___   _ __   ___   __| | ___ 
| | | | '_ \| | '__| / __| | '_ \ / _ \ / _` |/ _ \
| |_| | | | | | |  | \__ \ | | | | (_) | (_| |  __/
 \___/|_| |_|_|_|  |_|___/ |_| |_|\___/ \__,_|\___|
EOF
echo -e "${NC}"

export UNIRIS_P2P_PORT=P2P_PORT
export UNIRIS_WEB_SSL_CERT_PATH=SSL_CERT_PATH
export UNIRIS_WEB_SSL_KEY_PATH=SSL_KEY_PATH

echo -e ""
echo "Settings:"
echo "--------"
echo "P2P will expose the port: ${P2P_PORT}"
echo "SSL Certificate will be located at: ${SSL_CERT_PATH}"
echo "SSL Key will be located at: ${SSL_KEY_PATH}"
echo ""

if [ -f "$INSTALL_DIR/bin/uniris_node" ]; then
  ${INSTALL_DIR}/bin/uniris_node start
  pid = echo $!
  echo "Application is running in background (PID: ${pid})"
else
  echo -e "${RED}Error:"
  echo -e "Application not installed. Please execute 'install.sh' before"
  echo -e "${NC}"
  exit 1
fi
