# Bootstrapping 

ArchEthic Blockchain by using Network Transaction and Supervised Multicast, requires some actions to be performed 
when a node is bootstrapping. This operations will ensure synchronization and P2P awareness.

## Announcing

When a node wants the network the first time, it will request from a list of preconfigured nodes to reach (called "bootstrapping seeds"), the closest nodes from its position.

Then, it will generate a first node transaction including as data: ip, port, protocol, reward address, key certificate (to ensure the key is coming from an secure element)
Once the network will attest and verify its transaction, the node will be able to start a SelfRepair proecss

## Updates

When a nodes rejoin the network after some time, depending if its previous data expired, it will generate a new transaction with the new information

## Synchronization

Once the transaction is validated, the node will start by requesting the list of nodes.

Then, it will start the [Self-Repair](/network/p2p/self_repair.md) sequence to get and synchronize the missing transactions and publish its end of sync to the network.

By this way, the entire will know the existence the readyness of this node.
