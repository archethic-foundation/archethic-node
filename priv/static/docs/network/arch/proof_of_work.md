# Proof Of Work
 
Others blockchains are using the concept of `Proof of Work` to ensure an unpredictable and pseudo random election of block validation (mining).
<br />
But this technique requires a lot of energy consumption and can still be subject to exploit by HashRate control.

ArchEthic Blockchain is using a new kind of `Proof of Work` to ensure the authenticity of the transaction origination devices.
<br />
This allows the additional security requirements on transaction validation like:
- prohibit any transaction even in case of key theft
- allow user to consult their balance ony any smartphone but generate a transaction only on a trusted device
- enable the organizers of an election to ensure biometric identity of a voter

## Concepts

The `Proof Of Work` consists of finding the right public key associated to the `Origin Signature` of the transaction
<br />from a list of public keys known by the network.

This verification is performed during the `Validation Stamp` creation by the `Coordinator Node` and ensure the device is authorized to generate the transaction

## Origin Devices

Just like any other actor into the system, devices will have their own transaction chain allowing them to update their keys. 

> Each origin device public keys are grouped by family which helps nodes to determine which set of keys, must be played to produce the Proof of Work. (i.e: software, usb, biometric).

> Each origin device public key is encrypted and renewed by the network ensuring confidentiality and authenticity of devices.

