# ArchEthic

Welcome to the ArchEthic Node source repository ! This software enables you to build the first transaction chain and next generation of blockchain focused on scalability and human oriented.

ArchEthic features:
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

## Next features to appear very soon:
- OnChain Governance & Decentralized Code Source and Hot Release Upgrades

## Installation

Requirements:
- Libsodium: for the ed25519 to Curve25519 conversion 
- OpenSSL 1.11
- OTP 23: generation of ed25519 key pairs
- GMP (https://gmplib.org/)

Platforms supported:
- Linux (Ubuntu 18.04)
- Mac OS X

Requires ScyllaDB/Cassandra installation to use for the backend storage
(We recommand ScyllaDB as it's better in resource consumption and performances)

## Development

Requires Elixir 1.11

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

### Automation

Requires working `docker-compose`

To run few `archethic-node`s in testnet one could use mix task `archethic.testnet`:
```bash
mix archethic.testnet 5
```

The task will generate `docker-compose.json` (for 5 nodes with seeds: node1, node2, node3, node4, node5), and run `docker-compose -f docker-compose.json up` which in turn will build `archethic-node` image, and spawn 5 containers. To destroy these containers run `docker-compose -f docker-compose.json down` and use `docker image rm` to remove the image.

Run `mix help archethic.testnet` to see how to tweak the task.

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
