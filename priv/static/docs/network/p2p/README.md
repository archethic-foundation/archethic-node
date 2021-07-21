# P2P Layer

ArchEthic Blockchain redesigned the entire P2P layer to be more effective and support an unlimited permissionless network.

## Why do you need something new ?

In the current P2P and distributed networks, there are two methods of communication for discovery and data propagation: 
- the Gossip mode, whose properties are defined by the knowledge of the outgoing neighbors, which means each node of the network will discover the properties of the other nodes by interrogating them one by one, usually randomly, performing some unnecessary network traffic and sending data through nearest nodes for propagation.

- the Broadcast mode whose properties are defined by the knowledge of the incoming neighbors, which uses incoming connections and dispatch the data to all the nodes.

## Supervised Multicast

ArchEthic is using a hybrid communication that uses Supervised Multicast which is closer to the properties of Broadcast networks and combines the following properties:

> Transaction Replication Process: Capitalizing on incoming and outgoing con- nection information during the replication process

> Network Transaction Chains: Using transaction and consensus to attest when a node joins the network and is propaged throught all the nodes

> Beacons Chains: Which using snapshots and sampling of P2P availability and produce summaries each day to maintain a qualified vision of the network

> Data propogation: By using sharding and distributed replication, only the required nodes will receive information and use their bandwidth to transmit data through (avoiding a lot of traffic)

