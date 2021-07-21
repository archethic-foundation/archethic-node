# ARCH Consensus
 
ArchEthic Blockchain is using a new consensus called `ARCH` (Atomic Rotating Commitment Heuristic) for a uncompromising consensus to support
<br />
high scalability and high throughput.

ArchEthic Blockchain is based on three properties:

* Security: Each transaction is validated atomically
* Data consistency: Algorithms ensure to access the latest write and maximum availability
* Fault tolerance: Allow nodes to operate independently even in case of disaster


`ARCH` consensus is defined by three concepts:
- `Atomic Commitment`: The most absolute form a consensus which implies 100% of concordant responses for the acceptal or refusal of the transaction validation
- `Heuristic`: Set of algorithms which manages the entire network allowing to elect in a decentralized and coordinated way the nodes in charge to validate or store the transaction chains
- `Rotating`: Node election is constantly changing. No nodes can predict which nodes will validate the transaction before its arrives

## Atomic Commitment

ArchEthic Blockchain is based on `Hypergeometric distribution` laws which from an unpredictable election and formal consensus make it possible to obtain
<br />with certainty (99.99999999%) the same answer by querying 197 nodes as would be obtained by querying 100 000 nodes.

Therefore, it makes possible the consensus establishment with a small part of nodes and can resist to attacks of 90% of malicious nodes. 
<br />
The risk of related availability is ensure by a strict management of the disruptive nodes which are banished after investigation of the origin of the disagreement.

By supporting more 90% of malicious nodes into its network, `ARCH` consensus is above aeronautical or nuclear standard, thanks to the `Atomic Commitment` which 
<br />
request the total aggreement of the validation nodes and from a `Malicious Detection` algorithm to detect the malicious nodes.


## Rotating Election

Each rotating election is unpredictable but still verifiable and reproducible.
The rotating algorithm sort a list of nodes based on:
- `Hash of transaction`: Unpredictable until the transaction arrives
- `Daily nonce`: Secret shared between the authorized nodes and renewed daily
- `Node public key`: Last node public key

The rotating election produces a proof, named: `Proof of Election` which can be verified by any other nodes to ensure the right election of nodes.

From this algorithm, we get a list of nodes which can be filter according to the constraints of the validation of the transaction.
- P2P availability
- Geographical distribution

## Workflow

When a transaction is willing to be validated, its follows the given workflow:

1. The transaction is received by any node (aka `Welcome node`)
2. The `Welcome Node` determines the validation nodes from the `Rotating Election` algorithm and forward the transaction
3. The validation nodes after receiving the transaction start some preliminary job to gather the context of the transaction:
   - Previous transaction
   - List of unspent outputs
4. After the context building, the `Cross Validation Nodes` communicate to the `Coordinator Node` the list of storage nodes involved to gather those information.
5. The `Coordinator Node` can build the `Validation Stamp` and compute the replication tree. Then it transmits them to the `Cross Validation Nodes`.
6. The `Cross Validation Nodes` verify the content of the `Validation Stamp`, sign with or without inconsistencies and send the `Cross Validation Stamp` to all the validation nodes involved.
7. Once all the `Cross Validation Stamps` are received and if the `Atomic Commitment` is reached, the replication phase starts.
8. Validation nodes send the transaction to the respective storages nodes:
- Storage nodes responsible for the new transaction chain
- Storage nodes responsible for the outputs of the transactions (transaction's movements addresses, node movements, recipients)
- Storage nodes responsible for the [Beacon Chain](/network/beacon_chain.md)
9. The storage for the new transaction chain will notify the validation nodes and the `Welcome Node` about the replication, and the `Welcome Node` will notify the client about it.


 
