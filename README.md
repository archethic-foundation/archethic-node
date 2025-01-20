# Archethic

Welcome to the Archethic Node source repository ! This software enables you to build the first transaction chain and next generation of blockchain focused on scalability and human oriented.

Archethic features:

- Fast transaction processing (> 1M tps)
- Lower energy consumption than other blockchain
- Designed with a high level of security (ARCH consensus supporting 90% of maliciousness)
- Adaptive cryptographic algorithms (quantum resistant)
- Decentralized Identity and Self Sovereign Identity
- Smart contract platform powered by a built-in interpreter
- Strong scalability with geo secured sharding
- Soft-Real-Time P2P view with supervised networking

## Development

Our codebase aims to reach the guidelines of Elixir projects.
We are focusing on the best quality.

The source code can change to respect the best quality of reading and regarding best practices.

Current implemented features:

- Adaptive cryptography: different elliptic curves and software implementation
- Hybrid root of trust: mix of hardware and software cryptographic key to maintain trust and security
- TransactionChain: Transaction structure and transaction generation
- Smart Contract: interpreter coded with Elixir DSL through Meta-programming and AST
- Node election: heuristic validation and storage node selection
- P2P: Inter-node communication, supervised connection to detect the P2P view of nodes in almost real-time
- Transaction mining: ARCH consensus
- Beacon chain: Maintains a global view of the network (transactions, P2P view)
- Self-Repair: Self-healing mechanism allowing to resynchronize missing transactions
- Embedded explorer leveraging sharding to retrieve information
- Custom Binary protocol for data transmission
- Token minting
- Internal oracles (UCO Price Feed)
- Tailored embedded database

## Running a node for development purpose

### Using Elixir - MacOS specific setups

On Apple Silicon architecture, you might encounter issues running nodes.

Here is how to make it work.

#### Install openssl using brew

```sh
brew install openssl@3
```

#### Install erlang using `asdf`

```sh
cd <project_directory>
KERL_CONFIGURE_OPTIONS="--disable-jit --without-javac --without-wx --with-ssl=$(brew --prefix openssl@3)" asdf install
```

#### Locally update `exla` dependency

Edit `mix.exs` and replace the following `deps` item :

```elixir
      {:exla, "~> 0.5"},
```

by

```elixir
      {:exla, "~> 0.5.3"},
```

Then, install dependencies as usual :

```sh
mix deps.get
```

#### 🎉 You can run the node as usual

```sh
iex -S mix
```

### Using Elixir

Requirements:

- Libsodium: for the ed25519 to Curve25519 conversion
- OpenSSL 1.11
- Erlang OTP 25
- Elixir 1.14
- GMP (https://gmplib.org/)
- MiniUPnP used for port forwarding & IP lookup (https://miniupnp.tuxfamily.org/)
- Npm for static assets (https://nodejs.org/en/download)

Platforms supported:

- Linux (Ubuntu 18.04)
- Mac OS X ([See specific setups](#using-elixir---macos-specific-setups))

At first, clone the repository:

```bash
git clone https://github.com/archethic-foundation/archethic-node.git
cd archethic-node
```

Get dependencies:

```bash
mix deps.get
```

Install the static assets

```
cd assets ; npm install; cd -
```

To start a single node:

```bash
iex -S mix
```

To clean the data

```bash
make clean
```

To start mutiple node, you need to update some environment variables:

```bash
# Start the first node
iex -S mix

# Start second node
ARCHETHIC_CRYPTO_SEED=node2 ARCHETHIC_P2P_PORT=3003 ARCHETHIC_HTTP_PORT=4001 ARCHETHIC_HTTPS_PORT=5001 iex -S mix

# To start other node, increment the environment variables
```

### Using docker

Requires docker compose plugin

At first, clone the repository:

```bash
git clone https://github.com/archethic-foundation/archethic-node.git
cd archethic-node
```

Build the image:

```bash
docker build -t archethic-node .
```

To start a single node:

```bash
# You can run node up to node3
docker compose up node1
docker compose up node2
docker compose up node3
```

To start all nodes at the same time:

```bash
docker compose up
```

To run benchmarks:

```bash
docker compose up bench
```

To run the playbooks to validate non regression:

```bash
docker compose up validate
```

### Using snap

Work in progress ..

## Running a node for testnet / mainnet

Will be opened regarding roadmap advancement

## Contribution

Thank you for considering to help out with the source code.
We welcome contributions from anyone and are grateful for even the smallest of improvement.

Please to follow this workflow:

1. Fork it!
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create new Pull Request

## Licence

AGPL
