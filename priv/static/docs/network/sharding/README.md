# Sharding
 
To become a unlimited decentralized network, ArchEthic Blockchain is using a feature call `Sharding`
<br />
uses to split processing and storage power to ensure a scalable system.

Thanks to the `Transaction Chain` paradigm, transactions can be splitted into chain, to ensure a concurrent processing 
<br />
as the opposive of traditional blockchains.

Other new blockchain networks start to use `Sharding` but sometimes no in a complete form: 
- either storage
- either validation

ArchEthic Blockchain supports a complete shardind scheme for validation and for storage.

## Validation

Each transaction is validated by a new set of rotating nodes.
<br />
This ensure the distribution of validation and the processing, to achieve a linear scalability and a high TPS.

Because transaction are using the UTXO model, there is not reality out of the transaction, so the network is not subject to issue like :
- cross shards synchronization
- state channels communication

To get the state of a transaction, only the transaction and the transaction inputs will be taken into consideration

## Storage

After the validation of the transaction, validation nodes will be in charge to send the transaction to several pool of nodes:
- Transaction Chain Storage Pool: All the transaction associated with the same chain must be replicated on the storage nodes associated with the new transaction's address.
- I/O Storage Pool: Each validated transaction is replicated on the storage nodes associated with the addresses of the transaction input/outputs:
  - Transaction movements addresses storage pools
  - Node movements public key storage pools
  - Recipients addresses storage pools
- Beacon Storage Pool: Each transaction address must be replicated on the storage nodes of the associated address subset [See BeaconChain](/network/beacon_chain.md)

> For each transaction, the Transaction Chain Storage Pool will change, assuring a completed distribution of nodes and the data replication. Nevertheless, nothing prevents the storage nodes to overlap within the chain.

## Rotating Election

Like the validation nodes election, storage nodes election is subject to a rotating election.
<br />In other terms, each transaction will have its own shard and storage nodes.

The storage node election is based on:
- the address of the transaction
- the storage nonce: a stable secret known by the network
- the list of nodes

This permits any node to perform this computation autonomously to reproduce this list and to request transaction from the closest node.

To ensure the best availability of the data, this list is refined by some critierias such as:
- P2P availability
- Geographical distribution

