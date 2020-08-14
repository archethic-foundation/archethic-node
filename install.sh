#!/bin/bash

BLUE='\033[1;34m'
NC='\033[0m'
CYAN='\033[1;36m'

usage() {
  echo "Usage:"
  echo ""
  echo " Install Uniris node dependencies and application"
  echo ""
  echo "  " install.sh [-d  dir] " Specify the installation dir"
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

echo -e "${CYAN}"
echo "-------------------------"
echo "Dependencies installation"
echo "-------------------------"
echo -e "${NC}"

echo -e "${CYAN}"
echo "1/ System requirements..."
echo -e "${NC}"

apt-get update && apt-get install -y wget gnupg2 build-essential -y locales git libz-dev && \
    locale-gen en_US.UTF-8

echo -e "${CYAN}"
echo "2/ OpenSSL..."
echo -e "${NC}"

cd /usr/local/src/ && sudo wget https://www.openssl.org/source/openssl-1.1.1g.tar.gz && \
    sudo tar -xf openssl-1.1.1g.tar.gz && \
    cd openssl-1.1.1g && \
    sudo ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib && \
    sudo make && sudo make install && \
    sudo echo "/usr/local/ssl/lib" >> /etc/ld.so.conf.d/openssl-1.1.1g.conf && \
    sudo ldconfig && \
    sudo echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/local/ssl/bin" >> /etc/environment && \
    source /etc/environment && \
    sudo ln -s /etc/ssl/certs/*.* /usr/local/ssl/certs/ && \
    cd ~ 

echo -e "${CYAN}"
echo "3/ Erlang/Elixir..."
echo -e "${NC}"

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && \
    dpkg -i erlang-solutions_2.0_all.deb && \
    apt-get update && \
    apt-get install -y esl-erlang elixir

echo -e "${CYAN}"
echo "4/ Libsodium..."
echo -e "${NC}"

wget https://download.libsodium.org/libsodium/releases/LATEST.tar.gz && \
    tar zxvf LATEST.tar.gz && \
    cd libsodium-stable && \
    ./configure && \
    make && make check && \
    make install && \
    ldconfig

echo -e "${CYAN}"
echo "4/ Docker..."
echo -e "${NC}"

sudo apt-get update && \
    apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update && \
    apt-get install docker-ce docker-ce-cli containerd.io

echo -e "${CYAN}"
echo "-------------------------"
echo "Application installation"
echo "-------------------------"
echo -e "${NC}"

if [ -z "$INSTALL_DIR" ]
then
    ./release.sh -d $INSTALL_DIR
else
    ./release.sh
fi