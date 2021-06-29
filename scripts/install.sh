#!/bin/bash

INSTALL_DIR=~/aebot
SCRIPT_DIR=$(dirname $(readlink -f $0))

echo "Install required system dependencies"

sudo apt-get update

sudo apt-get install -y \
  wget \
  gnupg2 \
  build-essential \
  locales \
  git \
  zlib1g-dev \
  libgmp-dev \
  nodejs \
  npm

sudo locale-gen en_US.UTF-8

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

echo "Install OpenSSL"

OPENSSL_VERSION=$(openssl version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
if [[ $(version_to_int $OPENSSL_VERSION) -lt $(version_to_int "1.1.1") ]]; then
    cd /usr/local/src/
    sudo wget https://www.openssl.org/source/openssl-1.1.1g.tar.gz 
    sudo tar -xf openssl-1.1.1g.tar.gz 
    cd openssl-1.1.1g 
    sudo ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib
    sudo make
    sudo make install
    suco bash -c 'echo "/usr/local/ssl/lib" >> /etc/ld.so.conf.d/openssl-1.1.1g.conf'
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

wget -O $INSTALL_DIR/erlang-solutions_2.0_all.deb https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb

sudo dpkg -i $INSTALL_DIR/erlang-solutions_2.0_all.deb

sudo apt-get update
sudo apt-get install -y esl-erlang elixir

echo "Install Libsodium"

if [[ $(ls /usr/local/lib | grep -c 'libsodium') -gt 0 ]]; then
  echo "Libsodium already installed"
else
 wget -O $INSTALL_DIR/libsodium-stable.tar.gz https://download.libsodium.org/libsodium/releases/LATEST.tar.gz
 tar zxvf $INSTALL_DIR/libsodium-stable.tar.gz -C $INSTALL_DIR
 cd $INSTALL_DIR/libsodium-stable
 ./configure
 make
 sudo make install
 sudo ldconfig
 cd ~
fi

echo "Install docker"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Install docker"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io


echo "Install ScyllaDB"

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 5e08fbd8b5d6ec9c

sudo curl -L --output /etc/apt/sources.list.d/scylla.list http://downloads.scylladb.com/deb/ubuntu/scylla-4.3-$(lsb_release -s -c).list

sudo apt-get update
sudo apt-get install -y scylla

sudo apt-get update
sudo apt-get install -y openjdk-8-jre-headless
sudo update-java-alternatives --jre-headless -s java-1.8.0-openjdk-amd64

sudo scylla_setup --no-raid-setup --no-ec2-check --no-kernel-check --no-verify-package --no-sysconfig-setup --io-setup=1 --no-version-check --no-cpuscaling-setup --no-fstrim-setup --no-memory-setup --no-swap-setup

sudo scylla_memory_setup --memory=8G
sudo scylla_cpuset_setup --cpuset 2

sudo systemctl start scylla-server
nodetool status

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

git clone https://github.com/tpm2-software/tpm2-tss.git $INSTALL_DIR/tpm2-tss
cd $INSTALL_DIR/tpm2-tss
./bootstrap
./configure --with-udevrulesdir=/etc/udev/rules.d
make -j$(nproc)

sudo make install
sudo sed -i "s/tss/$(whoami)/gi" /etc/udev/rules.d/tpm-udev.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo ldconfig
sudo apt install tpm2-tools

cd $SCRIPT_DIR/..
make

FILENAME=`cat /sys/class/net/eno1/address`
echo Generating Keys - It may take a while...
./priv/c_dist/tpm_keygen > $INSTALL_DIR/$FILENAME 
echo Certified keys stored at $INSTALL_DIR/${FILENAME}

cd ~
