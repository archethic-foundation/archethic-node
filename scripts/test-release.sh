#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

SCRIPT_DIR=$(dirname $(readlink -f $0))
INSTALL_DIR1=$(readlink -f $SCRIPT_DIR/../test_release_node1)
INSTALL_DIR2=$(readlink -f $SCRIPT_DIR/../test_release_node2)

UPGRADE=0
INSTALL=0
PREPARE=0
export MIX_ENV=dev

usage() {
  echo "Usage:"
  echo ""
  echo " Create a test release Archethic node binary"
  echo ""
  echo "  " release.sh -i "       Create and install release"
  echo "  " release.sh -u "       Upgrade the release"
  echo "  " release.sh -h "       Print the help usage"
  echo ""
}

while getopts ":uiph" option; do
  case "${option}" in
  u) UPGRADE=1 ;;
  p) PREPARE=1 ;;
  i) INSTALL=1 ;;
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
shift $((OPTIND - 1))

# For every commands:
cd $SCRIPT_DIR/..

VERSION=$(grep 'version:' mix.exs | cut -d '"' -f2)
echo ""
echo "Version: ${VERSION}"
echo "Installation dir node1: ${INSTALL_DIR1}"
echo "Installation dir node2: ${INSTALL_DIR2}"

# Split commands logic
if [ $UPGRADE == 1 ]; then
  echo "Running the upgrade"
  $INSTALL_DIR1/bin/archethic_node upgrade $VERSION &
  $INSTALL_DIR2/bin/archethic_node upgrade $VERSION &
  exit
fi

# Install updated versions of hex/rebar
mix local.rebar --force
mix local.hex --if-missing --force

# Fetch deps and compile
mix deps.get

# Builds WEB assets in production mode
npm --prefix ./assets ci --progress=false --no-audit --loglevel=error
mix assets.saas
mix assets.deploy

# Create a release folder for each nodes
mkdir -p $INSTALL_DIR1
mkdir -p $INSTALL_DIR2

if [ $PREPARE == 1 ]; then
  echo "Building the upgrade release"
  mix distillery.release --upgrade

  # cp the .tar.gz for distillery
  mkdir -p $INSTALL_DIR1/releases/$VERSION
  mkdir -p $INSTALL_DIR2/releases/$VERSION
  cp _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR1/releases/$VERSION/archethic_node.tar.gz
  cp _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR2/releases/$VERSION/archethic_node.tar.gz

  # but we unpack them ourselves to avoid distillery skipping unpack
  tar -xf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR1
  tar -xf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR2

  # update node2 name
  sed -i 's/archethic_node/archethic_node2/g' $INSTALL_DIR2/releases/$VERSION/vm.args

  echo "Release has been prepared"
  echo "Next step is to upgrade the running node: ./scripts/test-release.sh -u"
elif [ $INSTALL == 1 ]; then
  echo "Building the release"
  # create the release
  mix distillery.release

  # unpack it
  tar -xf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR1
  tar -xf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR2

  # update node2 name
  sed -i 's/archethic_node/archethic_node2/g' $INSTALL_DIR2/releases/$VERSION/vm.args

  echo "Release has been installed"
  echo "To run the release: ./test_release/bin/archethic_node console"
  echo "To test the upgrade, change git branch, update mix.exs version and run ./script/test-release.sh -p to prepare release then ./script/test-release.sh -u to run the upgrade"
fi
