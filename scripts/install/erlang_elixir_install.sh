#!/bin/bash

echo "Install Erlang & Elixir"

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

function version_to_int {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

ERLANG_BIN=$(which erl)

if [[ $ERLANG_BIN == "" ]]; then
  wget -O ~/erlang-solutions_2.0_all.deb https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
  sudo dpkg -i ~/erlang-solutions_2.0_all.deb
else
  OTP_VERSION=$(erl -noshell -eval 'erlang:display(erlang:system_info(system_version))' -eval 'init:stop()' | perl -nle 'm/Erlang\/OTP ([^ ]*)/; print $1')
  if [[ $OTP_VERSION -lt 23 ]]; then
    wget -O ~/erlang-solutions_2.0_all.deb https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
    sudo dpkg -i erlang-solutions_2.0_all.deb
  else
    echo "Erlang OTP version up to date"
  fi
fi

ELIXIR_BIN=$(which elixir)
if [[ $ELIXIR_BIN == "" ]]; then
  sudo apt-get update
  sudo apt-get install -y esl-erlang elixir
else
  ELIXIR_VERSION=$(elixir --version | perl -nle 'print $1 if m/Elixir ([^ ]*)/')
  if [ $(version_to_int $ELIXIR_VERSION) -lt $(version_to_int '1.10') ]; then
      sudo apt-get update
      sudo apt-get install -y esl-erlang elixir
  else
    echo "Elixir up to date"
  fi
fi

