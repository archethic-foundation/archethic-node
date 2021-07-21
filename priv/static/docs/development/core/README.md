# Core Development

ArchEthic Node repository can be found [here](https://github.com/archethic-foundation/archethic-node)


## Technology Stack

ArchEthic Blockchain node used:
- Elixir
- C
- ScyllaDB

### Why Elixir ?

Elixir is a dynamic, functional language for building scalable and maintainable applications.

It leverages the Erlang VM, known for running low-latency, distributed, and fault-tolerant systems. <br />Elixir is successfully used in web development, embedded software, data ingestion, and multimedia processing, across a wide range of industries

When we are building P2P systems and Blockchain technologies we need to think about fault-tolerance, low-latency, concurrent/parallelism.
Elixir matches all those requirements </br /> 
Because All Elixir code runs inside lightweight threads of execution (called processes) that are isolated and exchange information via messages, we can build fast
processing of data which result in a high TPS for a better scalability.

The unavoidable truth about software running in production is that things will go wrong. <br />
Even more when we take network, file systems, and other third-party resources into account. <br />
Elixir provides supervisors which describe how to restart parts of your system when things go awry, going back to a known initial state that is guaranteed to work. <br />
This feature ensures in case on failure, the entire system will not be down, and the isolation provided by the processes and their restarsting strategy helps us to achieve it.

Functional programming promotes a coding style that helps developers write code that is short, concise, and maintainable.

Out of the box, Erlang VM provides the capability to hot reload code which is the best case scenarion if we want to provide an on-chain governance without restarting nodes.

### Why C ?

We need to interact with hardware components and C seems the best candidate, so we are using this language to communicate with TPM for instance. <br />
But also, for some intensive task which are really complex in computing, we rely C to perform those processing.

### Why ScyllaDB ?

ScyllaDB is a NoSQL database built from the idea of Cassandra - Wide Column Database - but with more efficiency in term of memory consumption and CPU processing.
As it's implemented in C++, it's faster and lightweight and takes advantage of low-level Linux primitives

We are using a Wide Column Database but we want to be able to fetch only some part of the data, so a column database fits really well for this kind of purpose.
Moreover, we want a database with a high throughput in writing and ScyllaDB fits really well with its LSM storage engine.

## Structure

Code base is splitted into domains (contexts) for better single responsibility principle:
- `TransactionChain`: Manage transaction data structure and chain management
- `DB`: Manage all the database queries
- `Crypto`: Manage all the cryptographic operations
- `P2P`: Manage the P2P node listing and node communication
- `Election`: Manage the node election algorithms
- `Mining`: Manage transaction validation
- `Replication`: Manage the replication
- `BeaconChain`: Manage BeaconChain subset and synchronization
- `OracleChain`: Manage OracleChain services, polling and scheduling
- `SharedSecrets`: Manage Shared Secrets scheduling and listing
- `SelfRepair` : Manage the SelfRepair scheduling
- `Bootstrap`: Manage the node bootstrapping
