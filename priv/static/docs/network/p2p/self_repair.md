# Self-Repair

ArchEthic Blockchain is using a self-repair mechanism to be able to sync/re-sync missing transactions to be able
<br />to restore the state of a node.

Because ArchEthic is using a multidimensional sharding, a node needs to execute a self-repair on multiple occasions, to ensure data availability and security:
- When the node bootstrap
- When a node goes offline
- When the code and heuristic algorithms changes

## Identification

To be able to determine which transactions are missing, foreach cycle of repair, a date of last sync is persisted.
Therefore, we can decide from this date, the list of missing BeaconChain transactions to sync. (Reminder: BeaconChain summaries transactions across the entire network each day)

The Self-Repair will then request BeaconChain storage pools to get the missing transactions from those missing days

## Synchronization

Because we are using rotating election, nodes need to perform the `Storage Node Election` to determine if they need to store this transaction.

In that case, we will get the list existing storages nodes from the transaction's address to sync and request from the closest nodes the transaction to be replicated.

Once finalized, a new last date of sync is persisted for the next cycle.

