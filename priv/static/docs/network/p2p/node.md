# Node

ArchEthic is using a structured and open P2P network based on some properties:

## Structure and Authentication 
Each node know the entire list of nodes allowed to participate in the network through the use of Node transaction chains.
Therefore, each connection is encrypted and authenticated by the last node public key

A node include a list P2P information such as:
- IP
- Port
- P2P Protocol (i.e TCP)
- First public key
- Last public key
- GeoPatch (for geographical distribution based on the GeoIP of the IP)
- NetworkPatch (for P2P responsivness based on the latency to reach it)
- Reward address (the address where the mining rewards should be sent)
- Global availability (from BeaconChain qualification)
- Local availability (from Supervised Multicast)
- Average availability (from BeaconChain qualification)
- Authorized
- Authorization Date

## Permisionless:
Any node can participate into the network as long as they have some hardware requirements such secure element to enclave the private keys
avoiding any disclosure of keys. 
Currently we are supporting: TPM 2.0
But others providers will be available with the time

However the network decides by itself, if it needs for validation nodes.

## Remuneration

Each is node is remunerated according to the its contribution to the network:
- for validation
- for information provision during the validation

!> A node is not remunered to replicate a transaction but it will be when it makes the transactions available to the network for the next transaction processing

> However, if a validation node didn't receive enough a mining rewards during the month, the Network Pool (from the UCO distribution) will send compensation. <br />
<br />
For example: if a node receive 30$ equivalent UCO, and if the rules say the minimum should be 50$, then the network pool will send 20$ to this node. <br />
  if this node receive 100$ of mining rewards, the network pool will node send any UCO to this node.  
