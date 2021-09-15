#!/bin/bash

set -e
trap 'echo "******* FAILED *******" 1>&2' ERR

USER=$(whoami)
INSTALL_DIR=/home/$USER/aebot/build
UPGRADE=0

usage() {
  echo "Usage:"
  echo ""
  echo " Release ArchEthic node binary"
  echo ""
  echo "  " release.sh [-d  dir] " Specify the installation dir"
  echo "  " release.sh -u "       Upgrade the release"
  echo "  " release.sh -h "       Print the help usage"
  echo ""
}

while getopts :uhd: option
do
    case "${option}"
    in
        d) INSTALL_DIR=${OPTARG};;
        u) UPGRADE=1;;
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

# Install updated versions of hex/rebar
mix local.rebar --force
mix local.hex --if-missing --force

export MIX_ENV=prod

# Fetch deps and compile
mix deps.get

# Builds WEB assets in production mode
cd assets
npm ci
npm run deploy
cd -
mix phx.digest

VERSION=$(grep 'version:' mix.exs | cut -d '"' -f2)
echo ""
echo "Version: ${VERSION}"
echo "Installation dir: ${INSTALL_DIR}"

mkdir -p $INSTALL_DIR

if [ $UPGRADE == 1 ]
then
    # Build upgrade releases
    echo "Build the upgrade release"
    MIX_ENV=prod mix distillery.release --upgrade

    echo "Copy upgraded release into ${INSTALL_DIR}/releases/${VERSION}"

    cp _build/prod/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz $INSTALL_DIR/releases/$VERSION

    echo "Run the upgrade"
    $INSTALL_DIR/bin/archethic_node upgrade ${VERSION}
else
    # Build and install the releases

    echo "Generate release"
    MIX_ENV=prod mix distillery.release

    echo "Install release"
    tar zxvf _build/prod/rel/archethic_node/releases/$VERSION/archethic_node.tar.gz -C $INSTALL_DIR
    echo "Release has been installed on ${INSTALL_DIR}"

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
    
    Restart=on-failure
    RemainAfterExit=yes
    RestartSec=5
    
    LimitNOFILE=65535
    UMask=0027
    SyslogIdentifier=archethic
    
    [Install]
    WantedBy=multi-user.target
EOF

    # restart daemon, enable and start service
    echo "Reloading daemon and enabling service"
    sudo systemctl daemon-reload 
    sudo systemctl enable archethic
    sudo systemctl start archethic
    echo "Service Started"
fi

exit
