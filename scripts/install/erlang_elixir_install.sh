#!/bin/bash

echo "Install Erlang & Elixir"

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

wget -O ~/erlang-solutions_2.0_all.deb https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb

sudo dpkg -i ~/erlang-solutions_2.0_all.deb

sudo apt-get update
sudo apt-get install -y esl-erlang elixir

