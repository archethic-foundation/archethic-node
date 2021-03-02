#!/bin/bash

NC='\033[0m'
CYAN='\033[1;36m'

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

[[ $UID == 0 ]] || { echo "This script must be run as root."; exit 1;}

echo -e "${CYAN}"
echo "-------------------------"
echo "Dependencies installation"
echo "-------------------------"
echo -e "${NC}"

echo -e "${CYAN}"
echo "1/ System requirements..."
echo -e "${NC}"

apt-get update && apt-get install -y wget gnupg2 build-essential -y locales git libz-dev libgmp-dev && \
    locale-gen en_US.UTF-8

echo -e "${CYAN}"
echo "2/ OpenSSL..."
echo -e "${NC}"

OPENSSL_VERSION=$(openssl version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
if [[ $(version_to_int $OPENSSL_VERSION) -lt $(version_to_int "1.1.1") ]]; then
  cd /usr/local/src/ && wget https://www.openssl.org/source/openssl-1.1.1g.tar.gz && \
    tar -xf openssl-1.1.1g.tar.gz && \
    cd openssl-1.1.1g && \
    ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib && \
    make && make install && \
    echo "/usr/local/ssl/lib" >> /etc/ld.so.conf.d/openssl-1.1.1g.conf && \
    ldconfig && \
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/local/ssl/bin" >> /etc/environment && \
    source /etc/environment && \
    ln -s /etc/ssl/certs/*.* /usr/local/ssl/certs/ && \
    cd ~
else
  echo "OpenSSL up to date"
fi

echo -e "${CYAN}"
echo "3/ Erlang/Elixir..."
echo -e "${NC}"

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

ERLANG_BIN=$(which erl)

if [[ $ERLANG_BIN == "" ]]; then
  wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && \
    dpkg -i erlang-solutions_2.0_all.deb
else
  OTP_VERSION=$(erl -noshell -eval 'erlang:display(erlang:system_info(system_version))' -eval 'init:stop()' | perl -nle 'm/Erlang\/OTP ([^ ]*)/; print $1')
  if [[ $OTP_VERSION -lt 23 ]]; then
    wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && \
      dpkg -i erlang-solutions_2.0_all.deb
  else
    echo "Erlang OTP version up to date"
  fi
fi

ELIXIR_BIN=$(which elixir)
if [[ $ELIXIR_BIN == "" ]]; then
  apt-get update && apt-get install -y esl-erlang elixir
else
  ELIXIR_VERSION=$(elixir --version | perl -nle 'print $1 if m/Elixir ([^ ]*)/')
  if [ $(version_to_int $ELIXIR_VERSION) -lt $(version_to_int '1.10') ]; then
      apt-get update && apt-get install -y esl-erlang elixir
  else
    echo "Elixir up to date"
  fi
fi

echo -e "${CYAN}"
echo "4/ Libsodium..."
echo -e "${NC}"

if [[ $(ls /usr/local/lib | grep -c 'libsodium') -gt 0 ]]; then
  echo "Libsodium already installed"
else
  wget https://download.libsodium.org/libsodium/releases/LATEST.tar.gz && \
    tar zxvf LATEST.tar.gz && \
    cd libsodium-stable && \
    ./configure && \
    make && make install && \
    ldconfig
fi

echo -e "${CYAN}"
echo "4/ Docker..."
echo -e "${NC}"

apt-get update && \
    apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io

