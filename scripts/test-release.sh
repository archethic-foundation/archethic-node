#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

SCRIPT_DIR=$(dirname $(readlink -f $0))

UPGRADE=0
INSTALL=0
PREPARE=0
NB_OF_RELEASES=0
UPFROM=latest
export MIX_ENV=dev

usage() {
  echo "Usage:"
  echo ""
  echo " Create a test release Archethic node binary"
  echo ""
  echo "  " release.sh -i "       Create and install release"
  echo "  " release.sh -p "       Prepare the release for hot reload"
  echo "  " release.sh -u "       Upgrade the release"
  echo "  " release.sh -n "       Set the number of node to apply the command"
  echo "  " release.sh -v "       Specifiy the version to up from, works only with -p"
  echo "  " release.sh -h "       Print the help usage"
  echo ""
}

while getopts ":uiphn:v:" option; do
  case "${option}" in
  u) UPGRADE=1 ;;
  p) PREPARE=1 ;;
  i) INSTALL=1 ;;
  n) 
    if [[ ${OPTARG} =~ ^[0-9]+$ ]]; then
      NB_OF_RELEASES=${OPTARG}
    else
      usage
      exit 1
    fi
    ;;
  v) 
    UPFROM=${OPTARG};;
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

if [[ $NB_OF_RELEASES = 0 ]]; then
  NB_OF_RELEASES=2
fi

if [[ $UPFROM != "latest" && $PREPARE == 0 ]]; then
  usage
  exit 1
fi

# For every commands:
cd $SCRIPT_DIR/..

VERSION=$(grep 'version:' mix.exs | cut -d '"' -f2)
echo ""
echo "Version: ${VERSION}"

for (( i=1; i<=$NB_OF_RELEASES; i++ )); do
  INSTALL_DIR=$(readlink -f $SCRIPT_DIR/../test_release_node$i)
  echo "Installation dir node $i: ${INSTALL_DIR}"
done

build_deps() {
  # Install updated versions of hex/rebar
  mix local.rebar --force
  mix local.hex --if-missing --force

  # Fetch deps and compile
  mix deps.get

  # Builds WEB assets in production mode
  npm --prefix ./assets ci --progress=false --no-audit --loglevel=error
  mix assets.saas
  mix assets.deploy
}

update_tar_node_name() {
  PWD=$(pwd)
  DIR=$1
  VERSION=$2
  INDEX=$3

  cd $DIR/releases/$VERSION
  gunzip archethic_node.tar.gz
  tar -xf archethic_node.tar releases/$VERSION/vm.args
  sed -i "s/archethic_node/archethic_node$INDEX/g" releases/$VERSION/vm.args
  tar -uf archethic_node.tar releases/$VERSION/vm.args
  gzip archethic_node.tar
  rm -r releases

  cd $PWD
}

# Split commands logic
if [ $UPGRADE == 1 ]; then
  echo "Running the upgrade"

  for (( i=1; i<=$NB_OF_RELEASES; i++ )); do
    INSTALL_DIR=$(readlink -f $SCRIPT_DIR/../test_release_node$i)
    $INSTALL_DIR/bin/archethic_node upgrade $VERSION &
  done

  wait
elif [ $PREPARE == 1 ]; then
  echo "Building the upgrade release"

  build_deps

  if [[ $UPFROM == "latest" ]]; then
    mix distillery.release --upgrade
  else
    mix distillery.release --upgrade --upfrom $UPFROM
  fi

  # cp the .tar.gz for distillery
  echo "Copy release on $NB_OF_RELEASES release dir"
  for (( i=1; i<=$NB_OF_RELEASES; i++ )); do
    INSTALL_DIR=$(readlink -f $SCRIPT_DIR/../test_release_node$i)
    mkdir -p $INSTALL_DIR/releases/$VERSION
    cp _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR/releases/$VERSION/archethic_node.tar.gz
    update_tar_node_name $INSTALL_DIR $VERSION $i &
  done

  wait

  echo "Release has been prepared"
  echo "Next step is to upgrade the running node: ./scripts/test-release.sh -u"
elif [ $INSTALL == 1 ]; then
  echo "Building the release"

  build_deps

  # create the release
  mix distillery.release

  # Create a release folder for each nodes
  echo "Create release dir for $NB_OF_RELEASES nodes"
  for (( i=1; i<=$NB_OF_RELEASES; i++ )); do
    INSTALL_DIR=$(readlink -f $SCRIPT_DIR/../test_release_node$i)
    mkdir -p $INSTALL_DIR
    tar -xzf _build/dev/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR
    # Update node name
    sed -i "s/archethic_node/archethic_node$i/g" $INSTALL_DIR/releases/$VERSION/vm.args
  done

  echo "Release has been installed"
  echo "To run the release: ./test_release/bin/archethic_node console"
  echo "To test the upgrade, change git branch, update mix.exs version and run ./script/test-release.sh -p to prepare release then ./script/test-release.sh -u to run the upgrade"
fi

exit 0
