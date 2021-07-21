# Beacon Chain
 
ArchEthic Blockchain is using `Sharding` mechanism to ensure scalability in term of storage and validation.
<br />
But since there is no way in a well sharded and distributed network to know all the transaction in the system,
a `Beacon Chain` is used to keep a global synchronization and reference.

## Concepts

`Beacon Chain` is used as tracer/marker of a global state but to face some scalability issue, ArchEthic Blockchain is using `Sharding` also for the `BeaconChain`.

Which means than the `Beacon Chain` is sharded and splitted into `subset` defined by the transaction's address and a given date.
<br />
By example: a transaction's address starting by `0F` at a given day, will not be stored on the same subset as a transaction's address starting by `9F` for the same day.


## Transaction tracking and timestamping

Each time a transaction is validated, the validation nodes will send the transaction to the right Beacon Chain storage nodes, to transmit the address of the transaction and its timestamp.

For each Beacon Chain interval, a new slot is generated referencing all the transaction during this interval.
<br />
At the end of the day, a transaction chain is formed and a last transaction is computed to generate a summary of the current day for a given subset.

Because each transaction has its own storage nodes, `Beacon Chains` are balanced between the storage nodes to ensure a better scalability and distribution.

## Status and Network Coordinates of nodes

Beacon Chains also contain network status of the nodes where the public key starts by the Beacon Chain subset.

The storage nodes in each subset is in charge of:
- check the nodes availability
- gather networking information such as latency, bandwidth

At the end of the day, a transaction is formed as well and a last transaction is compute to generate a summary of node availability and network coordinates

## Slot

Each `Beacon Chain` is splitted during the day into multiple slots, defined by interval (for instance every 10 min).
<br />Those slot contains the following information:
- Transaction summaries: timestamping of the validated transactions
  - address: Transaction's address
  - timestamp: Transaction validation time
  - movements addresses: List of outputs addresses of the transaction
- End of node synchronization: timestamping when a node finished its synchronization
  - node public key: Node's first public key
  - timestamp: Time when the node synchronization ended
- P2P view:
     - availabilities: binary form of the availability of the sampled nodes for the given subset
     - network statistics: latency and bandwidth of the sampled nodes for the given subset
