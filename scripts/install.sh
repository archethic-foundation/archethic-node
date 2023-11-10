#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

INSTALL_DIR=~/aebot
echo "INSTALL_DIR=$INSTALL_DIR"

SCRIPT_DIR=$(dirname $(readlink -f $0))
mkdir -p $INSTALL_DIR
echo "Install required system dependencies"

# Prevent the node to sleep
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Prevent upgrade to prompt service restart
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf

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
  net-tools \
  libncurses5-dev \
  openssl \
  unzip \
  automake \
  libssl-dev \
  autoconf \

sudo locale-gen en_US.UTF-8

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

echo "Install Erlang & Elixir"

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

if [[ ! -d $HOME/.asdf ]]
then
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.10.2
fi

echo '. $HOME/.asdf/asdf.sh' >> ~/.profile
echo '. $HOME/.asdf/completions/asdf.bash' >> ~/.profile
source ~/.profile

asdf update

asdf plugin add erlang || :
asdf plugin add elixir || :
asdf plugin add nodejs || :

cd $SCRIPT_DIR/..

asdf install

ELIXIR_VERSION=$(asdf current elixir 2>&1 | grep -oP '\d\S+')
ERLANG_VERSION=$(asdf current erlang 2>&1 | grep -oP '\d\S+')
NODEJS_VERSION=$(asdf current nodejs 2>&1 | grep -oP '\d\S+')

asdf global elixir $ELIXIR_VERSION
asdf global erlang $ERLANG_VERSION
asdf global nodejs $NODEJS_VERSION

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

sudo add-apt-repository -y \
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
  uthash-dev \
  doxygen \
  libjson-c-dev \
  libini-config-dev \
  libcurl4-openssl-dev \
  acl

cd $INSTALL_DIR
wget https://github.com/tpm2-software/tpm2-tss/releases/download/3.2.1/tpm2-tss-3.2.1.tar.gz
tar -xf tpm2-tss-3.2.1.tar.gz --one-top-level=tpm2-tss --strip-components 1
rm tpm2-tss-3.2.1.tar.gz && cd tpm2-tss
./configure --with-udevrulesdir=/etc/udev/rules.d
make -j$(nproc)

sudo make install
sudo sed -i "s/tss/$(whoami)/gi" /etc/udev/rules.d/tpm-udev.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo ldconfig
sudo apt install tpm2-tools -y

cd $SCRIPT_DIR/..
make

IFACE=$(route | grep '^default' | grep -o '[^ ]*$')
FILENAME=`cat /sys/class/net/$IFACE/address`
echo Generating Keys - It may take a while...
./priv/c_dist/tpm_keygen > $INSTALL_DIR/$FILENAME
echo Certified keys stored at $INSTALL_DIR/${FILENAME}

cd ~
