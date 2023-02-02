#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

SCRIPT_DIR=$(dirname $(readlink -f $0))
INSTALL_DIR1=$(readlink -f $SCRIPT_DIR/../test_release_node1)
INSTALL_DIR2=$(readlink -f $SCRIPT_DIR/../test_release_node2)

UPGRADE=0
INSTALL=0
PREPARE=0

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

while getopts ":uiph" option
do
  case "${option}"
  in
    u) UPGRADE=1;;
    p) PREPARE=1;;
    i) INSTALL=1;;
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
shift $((OPTIND -1))

cd $SCRIPT_DIR/..

VERSION=$(grep 'version:' mix.exs | cut -d '"' -f2)
echo ""
echo "Version: ${VERSION}"
echo "Installation dir node1: ${INSTALL_DIR1}"
echo "Installation dir node2: ${INSTALL_DIR2}"

export MIX_ENV=dev

if [[ $UPGRADE == 1 ]]
then
  # Run upgrade
  echo "Run the upgrade"
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
cd assets
npm i
cd ..
mix assets.saas
mix assets.deploy

mkdir -p $INSTALL_DIR1
mkdir -p $INSTALL_DIR2

if [[ $PREPARE == 1 ]]
then
  # Build upgrade releases
  echo "Build the upgrade release for node1"
  MIX_ENV=dev mix distillery.release --upgrade

  echo "Copy upgraded release into ${INSTALL_DIR1}/releases/${VERSION}"
  mkdir -p $INSTALL_DIR1/releases/$VERSION
  cp _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR1/releases/$VERSION/archethic_node.tar.gz

  echo "Build the upgrade release for node2"
  sed -i 's/<%= release_name %>/archethic_node2/g' ./rel/vm.args
  MIX_ENV=dev mix distillery.release --upgrade

  echo "Copy upgraded release into ${INSTALL_DIR2}/releases/${VERSION}"
  mkdir -p $INSTALL_DIR2/releases/$VERSION
  cp _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR2/releases/$VERSION/archethic_node.tar.gz

  sed -i 's/archethic_node2/<%= release_name %>/g' ./rel/vm.args
else
  # Build and install the releases
  echo "Generate release for node1"
  MIX_ENV=dev mix distillery.release

  echo "Install release for node1"
  tar zxvf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR1
  echo "Release has been installed on ${INSTALL_DIR1}"

  echo "Generate release for node2"
  sed -i 's/<%= release_name %>/archethic_node2/g' ./rel/vm.args
  MIX_ENV=dev mix distillery.release

  echo "Install release for node2"
  tar zxvf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR2
  echo "Release has been installed on ${INSTALL_DIR2}"

  sed -i 's/archethic_node2/<%= release_name %>/g' ./rel/vm.args

  echo "To run the release: ./test_release/bin/archethic_node console"
  echo "To test the upgrade, change git branch, update mix.exs version and run ./script/test-release.sh -p to prepare release then ./script/test-release.sh -u to run the upgrade"
fi

exit
