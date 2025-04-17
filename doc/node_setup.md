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
