# Fee

ArchEthic Blockchain is using specific heuristic algorithms to ensure the best transaction's distribution.

The fees are calculated according to the real costs of the network (size, complexity) and is based on the real value of the UCO (using [Oracle Chain](/network/oracle_chain.md))

## Distribution

Transaction's fee are distributed across all the actors during the transaction validation:
- `Coordinator Node`: 10% 
- `Cross validation Nodes`: 40%
- `Storage Nodes`: 50%

The remaining 10% will go the `Network Pool` as a burn mechanism to ensure a programmable destruction of UCO. 
<br />
This mechanism will ensure a deflation and therefore a way to increase the value of each UCO

## Calculation

The transaction's fee computation is based on some properties:
- Transaction's value
- Number of recipient
- Size of the transaction
- Number of replicas
- Complexity of the smart contract (TODO)


> Minimum fee: 0.1$ of the current UCO price

> Transaction value fee: minimum_fee * ( transaction_value / (minimum_fee * 1000) ) 

!> In case, there is not value (no uco to spend), a minimum fee is applied corresponding of 0.1$ of UCO

> Each byte will cost: 10<sup>-9</sup> of the current UCO's price

> After one recipient, each will cost: 10% of the current UCO's price

Formula:
```
Transaction Fee = fee_for_value + fee_for_storage + fee_for_complexity + cost_per_recipient
```

  


