#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

INSTALL_DIR=~/aebot
SCRIPT_DIR=$(dirname $(readlink -f $0))
mkdir -p $INSTALL_DIR
echo "Install required system dependencies"

# Prevent the node to sleep
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sudo apt-get update

sudo apt-get install -y \
  wget \
  curl \
  gnupg2 \
  build-essential \
  locales \
  git \
  zlib1g-dev \
  libgmp-dev \
  nodejs \
  npm \
  net-tools

sudo locale-gen en_US.UTF-8

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

echo "Install OpenSSL"

OPENSSL_VERSION=$(openssl version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
if [[ $(version_to_int $OPENSSL_VERSION) -lt $(version_to_int "1.1.1") ]]; then
    cd /usr/local/src/
    sudo wget https://www.openssl.org/source/openssl-1.1.1q.tar.gz 
    sudo tar -xf openssl-1.1.1q.tar.gz 
    cd openssl-1.1.1q 
    sudo ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib
    sudo make
    sudo make install
    sudo bash -c 'echo "/usr/local/ssl/lib" >> /etc/ld.so.conf.d/openssl-1.1.1q.conf'
    sudo ldconfig
    sudo bash -c 'echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/local/ssl/bin" >> /etc/environment'
    sudo bash -c 'source /etc/environment'
    sudo ln -s /etc/ssl/certs/*.* /usr/local/ssl/certs/
    cd ~
else
  echo "OpenSSL up to date"
fi

echo "Install Erlang & Elixir"

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

wget -O  $INSTALL_DIR/erlang-solutions_2.0_all.deb  https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb

sudo dpkg -i $INSTALL_DIR/erlang-solutions_2.0_all.deb

sudo apt-get update
sudo apt-get install -y esl-erlang=1:24.*

mkdir -p ~/elixir
wget https://github.com/elixir-lang/elixir/releases/download/v1.14.1/elixir-otp-24.zip -O ~/elixir/Precompiled.zip

unzip ~/elixir/Precompiled.zip -d ~/elixir
echo 'PATH=$PATH:~/elixir/bin' >> ~/.bashrc
source ~/.bashrc

echo "Install Libsodium"

if [[ $(ls /usr/local/lib | grep -c 'libsodium') -gt 0 ]]; then
  echo "Libsodium already installed"
else
 wget -O $INSTALL_DIR/libsodium-stable.tar.gz  https://download.libsodium.org/libsodium/releases/LATEST.tar.gz
 tar zxvf  $INSTALL_DIR/libsodium-stable.tar.gz -C $INSTALL_DIR
 cd $INSTALL_DIR/libsodium-stable
 ./configure
 make
 sudo make install
 sudo ldconfig
 cd ~
fi

echo "Install docker"

curl -fsSL  https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Install TPM Software Stack"

sudo apt -y update
sudo apt -y install \
  autoconf-archive \
  libcmocka0 \
  libcmocka-dev \
  procps \
  iproute2 \
  build-essential \
  git \
  pkg-config \
  gcc \
  libtool \
  automake \
  libssl-dev \
  uthash-dev \
  autoconf \
  doxygen \
  libjson-c-dev \
  libini-config-dev \
  libcurl4-openssl-dev \
  acl

cd $INSTALL_DIR
wget  https://github.com/tpm2-software/tpm2-tss/releases/download/3.1.0/tpm2-tss-3.1.0.tar.gz
tar -xf tpm2-tss-3.1.0.tar.gz --one-top-level=tpm2-tss --strip-components 1
rm tpm2-tss-3.1.0.tar.gz && cd tpm2-tss
./configure --with-udevrulesdir=/etc/udev/rules.d
make -j$(nproc)

sudo make install
sudo sed -i "s/tss/$(whoami)/gi" /etc/udev/rules.d/tpm-udev.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo ldconfig
sudo apt install tpm2-tools

cd $SCRIPT_DIR/..
make

IFACE=$(route | grep '^default' | grep -o '[^ ]*$')
FILENAME=`cat /sys/class/net/$IFACE/address`
echo Generating Keys - It may take a while...
./priv/c_dist/tpm_keygen > $INSTALL_DIR/$FILENAME 
echo Certified keys stored at $INSTALL_DIR/${FILENAME}

cd ~
