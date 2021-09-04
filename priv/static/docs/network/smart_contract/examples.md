# Examples

## Recurrent transfer 

```
# Send 1.0 each to the given address each month

condition inherit: [
  type: transfer,
  uco_transfers: %{ "0D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC" => 1.0 }
]

actions triggered_by: interval, at: "0 0 1 * *" do
  set_type transfer
  add_uco_transfer to: "0D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC", amount: 1.0
end
```

## ICO / Crowdfunding

```

# Ensure the next transaction will be a transfer
condition inherit: [
  type: transfer,
  nft_transfers: size() == 1
  # TODO: to provide more security, we should check the destination address is within the previous transaction inputs 
]

# Define conditions to accept incoming transactions
condition transaction: [
  type: transfer, 
  uco_transfers: size() > 0
] 

actions triggered_by: transaction do
  # Get the amount of uco send to this contract
  amount_send = transaction.uco_transfers[contract.address]

  if amount_send > 0 do
      # Convert UCO to the number of tokens to credit. Each UCO worth 10000 token
      token_to_credit = amount_send * 10000 

      # Send the new transaction
      set_type transfer
      add_nft_transfer to: transaction.address, nft: contract.address, amount: token_to_credit
  end 
end
```
