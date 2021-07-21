# Messaging

ArchEthic Blockchain is used a brand new P2P layer from the Supervised Multicast, but to ensure the best data transmission possible,
<br />we are using two modern approaches: `Stream Multiplexer` and `Binary Protocol`. 

Those two features helps to achieve a low latency P2P messaging.

## Stream Multiplexer

Stream Multiplexing allows multiple independent logical streams to all share a common underlying transport stream and <br />
there are many independent streams of communication between peers and have several concurrent streams open at the same time with a given remote peer.

Stream Multiplexing amortize the overhead of establishing transport connection and helps to distinguish which messages to handle in a concurrent way.

```
|---------|                           |---------|
| Service |                           | Service |
|---------|                           |---------|
    | Msg ID: 2    |------------|         |
    |--------------| Connection |---------| Msg ID: 1
                   |    TCP     |
    |--------------|------------|---------|
    | Msg ID: 1                           | Msg ID: 2
|---------|                           |---------|
| Service |                           | Service |
|---------|                           |---------|
```

## Binary Protocol

Network latency is very important to reach an unlimited and really scalable network and using binary protocol helps to reduce bandwith.

Different kind of solutions existing for binary protocol: Protobuf, Avro, Thrift, MsgPack, etc..
<br />
However to support a custom and efficient binary serialization, ArchEthic uses it own binary protocol through the transport layer
to reduce and to optimize by the message the data to send.

This aspect is important, when we are dealing with bits, to reduce byte size.

For example, if we want to serialize this bitstring: 11100000
- With existing solutions we may end up with a list of 8 bytes
- With a custom solution we serialize it with only 1 byte 
