#!/bin/bash

SCRIPT_DIR=$(dirname $(readlink -f $0))

sh $SCRIPT_DIR/install/system_deps_install.sh
sh $SCRIPT_DIR/install/openssl_install.sh
sh $SCRIPT_DIR/install/erlang_elixir_install.sh
sh $SCRIPT_DIR/install/libsodium_install.sh
sh $SCRIPT_DIR/install/docker_install.sh
sh $SCRIPT_DIR/install/scylldb_install.sh
sh $SCRIPT_DIR/install/tpm_install.sh

