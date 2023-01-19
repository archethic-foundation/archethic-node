#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

USER=$(whoami)
INSTALL_DIR=/home/$USER/aebot/build
UPGRADE=0
PREPARE=0
SERVICE_CREATION=0

usage() {
  echo "Usage:"
  echo ""
  echo " Release Archethic node binary"
  echo ""
  echo "  " release.sh [-d  dir] " Specify the installation dir"
  echo "  " release.sh -u "       Upgrade the release"
  echo "  " release.sh -s "       Create a systemd service"
  echo "  " release.sh -h "       Print the help usage"
  echo ""
}

while getopts :suphd: option
do
  case "${option}"
  in
    d) INSTALL_DIR=${OPTARG};;
    u) UPGRADE=1;;
    p) PREPARE=1;;
    s) SERVICE_CREATION=1;;
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

source ~/.profile

if [[ -d $HOME/.asdf ]]
then

  SCRIPT_DIR=$(dirname $(readlink -f $0))

  cd $SCRIPT_DIR/..

  asdf install

  ELIXIR_VERSION=$(asdf current elixir 2>&1 | grep -oP '\d\S+')
  ERLANG_VERSION=$(asdf current erlang 2>&1 | grep -oP '\d\S+')
  NODEJS_VERSION=$(asdf current nodejs 2>&1 | grep -oP '\d\S+')

  asdf global elixir $ELIXIR_VERSION
  asdf global erlang $ERLANG_VERSION
  asdf global nodejs $NODEJS_VERSION
fi

VERSION=$(grep 'version:' mix.exs | cut -d '"' -f2)
echo ""
echo "Version: ${VERSION}"
echo "Installation dir: ${INSTALL_DIR}"

export MIX_ENV=prod

if [[ $UPGRADE == 1 ]]
then
  # Run upgrade
  echo "Run the upgrade"
  $INSTALL_DIR/bin/archethic_node upgrade $VERSION

  exit
fi

# Install updated versions of hex/rebar
mix local.rebar --force
mix local.hex --if-missing --force

# Fetch deps and compile
mix deps.get

# Builds WEB assets in production mode
cd assets
npm ci
cd ..
mix assets.saas
mix assets.deploy

mkdir -p $INSTALL_DIR

if [[ $PREPARE == 1 ]]
then
  # Build upgrade releases
  echo "Build the upgrade release"
  MIX_ENV=prod mix distillery.release --upgrade

  echo "Copy upgraded release into ${INSTALL_DIR}/releases/${VERSION}"
  mkdir -p $INSTALL_DIR/releases/$VERSION
  cp _build/prod/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR/releases/$VERSION/archethic_node.tar.gz
else
  # Build and install the releases
  echo "Generate release"
  MIX_ENV=prod mix distillery.release

  echo "Install release"
  tar zxvf _build/prod/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR
  echo "Release has been installed on ${INSTALL_DIR}"

  if [ $SERVICE_CREATION == 1 ]
  then
  
  echo "Creating service file"
  sudo bash -c 'cat > /etc/systemd/system/archethic.service' << EOF

  [Unit]
  Description=ARCHEthic service
  After=local-fs.target network.target
  
  [Service]
  Type=simple
  User=$USER
  Group=$USER
  
  WorkingDirectory=$INSTALL_DIR
  
  ExecStart=$INSTALL_DIR/bin/archethic_node foreground
  ExecStop=$INSTALL_DIR/bin/archethic_node stop
  
  EnvironmentFile=/etc/default/archethic.env
  Environment=LANG=en_US.utf8
  Environment=MIX_ENV=prod
  Environment=ERLANG_COOKIE=$ERLANG_COOKIE
  
  Restart=on-failure
  RemainAfterExit=yes
  RestartSec=5
  
  LimitNOFILE=65535
  UMask=0027
  SyslogIdentifier=archethic
  
  [Install]
  WantedBy=multi-user.target
EOF

  # restart daemon, enable
  echo "Reloading daemon and enabling service"
  sudo systemctl daemon-reload 
  sudo systemctl enable archethic
  fi
fi

exit
