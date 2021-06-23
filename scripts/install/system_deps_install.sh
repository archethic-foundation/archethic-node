#!/bin/bash

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
