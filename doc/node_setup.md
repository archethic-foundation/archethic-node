# Node setup

## Installation

Fetch the latest codebase by cloning the repository
```bash
git clone https://github.com/archethic-foundation/archethic-node.git
```

Install the required dependencies for the node to run:
```bash
cd archethic-node && ./scripts/install.sh
```

Install the release:

```bash
./scripts/release.sh -n [mainnet|testnet]
```

or

Install the release with systemd service:

```bash
./scripts/release.sh -s -n [mainnet|testnet]
```

## Environment configuration

Set environment file `archethic-network.env` file:

### Mainnet

```bash
MIX_ENV=prod
ARCHETHIC_LOGGER_LEVEL=debug
ARCHETHIC_VM_ARGS_NAME=mainnet@127.0.0.1
ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS=[IP OF THE BOOTSTRAPPING SEED]:30002:[PUB KEY OF THE BOOTSTRAPPING SEED]:tcp

# Desactivate port forwading (upnp not working or port opened manually)
# ARCHETHIC_NETWORKING_PORT_FORWARDING=false

# Retrieve public IP from remote (upnp not working)
# ARCHETHIC_NETWORKING_IMPL=REMOTE

# Set manually public IP
# ARCHETHIC_NETWORKING_IMPL=STATIC
# ARCHETHIC_STATIC_IP=XXX

# Use TPM origin key
# ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL=TPM
```

### Testnet

```bash
MIX_ENV=prod
ARCHETHIC_LOGGER_LEVEL=debug
ARCHETHIC_NETWORK_TYPE=testnet
ARCHETHIC_VM_ARGS_NAME=testnet@127.0.0.1
ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS=[IP OF THE BOOTSTRAPPING SEED]:30002:[PUB KEY OF THE BOOTSTRAPPING SEED]:tcp

# Desactivate port forwading (upnp not working or port opened manually)
# ARCHETHIC_NETWORKING_PORT_FORWARDING=false

# Retrieve public IP from remote (upnp not working)
# ARCHETHIC_NETWORKING_IMPL=REMOTE

# Set manually public IP
# ARCHETHIC_NETWORKING_IMPL=STATIC
# ARCHETHIC_STATIC_IP=XXX

# Use TPM origin key
# ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL=TPM
```
