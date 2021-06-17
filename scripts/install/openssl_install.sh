#!/bin/bash

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

echo "Install OpenSSL"

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
