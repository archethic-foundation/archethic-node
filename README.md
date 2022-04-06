# Archethic

Welcome to the Archethic Node source repository ! This software enables you to build the first transaction chain and next generation of blockchain focused on scalability and human oriented.

Archethic features:
- Fast transaction processing (> 1M tps)
- Lower energy consumption than other blockchain (3.6 Billion times less energy consumption than Bitcoin)
- Designed for the highest level of security (ARCH consensus can handle upto 90% of maliciousness)
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
- TransactionChain: Transaction structure and transaction generation
- Smart Contract: interpreter coded with Elixir DSL through Meta-programming and AST
- Node election: heuristic validation and storage node selection
- P2P: Inter-node communication, supervised connection to detect the P2P view of nodes in almost real-time
- Transaction mining: ARCH consensus
- Node bootstrapping
- Beacon chain: Track new transactions and node readiness
- Self-Repair: Self-healing mechanism allowing to resynchronize missing transactions
- Node shared secrets renewal: Integration of authorized validation nodes using heuristic constraints
- P2P transfers 
- Transaction explorer
- Custom Binary protocol leveraging Binary Pattern Matching and BitVectors
- NFT creation and transfers
- Integrated Oracle Chain (UCO Price Feed)
- Efficient transaction fee

## Development Roadmap

### Short term
These are the features will be implemented very soon (already in the pipe of the core team)
- Decentralized Wallet & Identity
- Yubikey integration for node enrollment and key management
- Provide exception on the smart contract inherit constraints
- Network coordinates aggregation from the BeaconChain

### Mid-Long term:
These are the feature which will be implemented after the short term roadmap but which are important:
- OnChain Governance & Decentralized Code Source and Hot Release Upgrades
- SGX integration for enclaving the node shared secrets
- Smart Contract Builder / Generator
- Smart UTXO: Provide code inside an UTXO to be executed when it's consumed
- On-chain time management through BeaconChain to ensure clock synchronisation

## Installation

Requirements:
- Libsodium: for the ed25519 to Curve25519 conversion 
- OpenSSL 1.11
- Erlang OTP 24
- Elixir 1.12
- GMP (https://gmplib.org/)

Platforms supported:
- Linux (Ubuntu 18.04)
- Mac OS X

## Development

At first, get dependencies:
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

To start multiple nodes, you can leverage: `docker-compose`

### Development with `docker-compose`

Requires working `docker-compose`

Build the image:
```bash
docker build -t archethic-node .
```

To start testnet:
```bash
docker-compose up
```

To run benchmarks:
```bash
docker-compose up bench
```

To run the playbooks to validate non regression:
```bash
docker-compose up validate
```

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
