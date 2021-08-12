# Local Testnet

To test and build on top of ArchEthic network, we encourage people to test with a local instance.

## Installation

- Clone the repository: 
```bash
git clone https://github.com/archethic-foundation/archethic-node.git
```

- Setup the dev environment:

  - [Install Elixir](https://elixir-lang.org/install.html)
  - [Install NodeJS](https://nodejs.org/en/download/)
  - [Install GMP](https://gmplib.org)
  - [Install ScyllaDB](https://www.scylladb.com/download/#server)
  
- Fetch the dependencies
```bash
mix deps.get
```

- Build web assets
```bash
cd assets ; npm install; cd -
``` 

- Start instance
```bash
iex -S mix
```

## Funding addresses

To be able to fund some addresses you can specify in the configuration which will be the addresses and the amount as genesis pool during the network initialization

- Ensure a fresh start
```bash
make clean
```

- Restart the node with some configuration
```bash
rm -rf ./_build
ARCHETHIC_TESTNET_GENESIS_ADDRESS=YOUR_ADDRESS_IN_HEXADECIMAL ARCHETHIC_TESTNET_GENESIS_AMOUNT=AMOUNT_TO_ALLOCATE iex -S mix
```

- Check the balance

Go to http://localhost:4000/explorer/transaction/{TYPE_YOUR_ADDRESS_IN_HEXADECIMAL}

It should displays some unspent outputs (in the "Ledger inputs" section) 
