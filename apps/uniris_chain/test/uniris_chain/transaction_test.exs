defmodule UnirisChain.TransactionTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.Data.Ledger
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer
  alias UnirisCrypto, as: Crypto

  test "from_seed/4 should create a new transaction and store the new keypair" do
    Crypto.add_origin_seed("origin_seed")

    assert %Transaction{} =
             Transaction.from_seed("myseed", :transfer, %Data{
               ledger: %Ledger{
                 uco: %UCO{
                   transfers: [%Transfer{to: "", amount: 10}]
                 }
               }
             })
  end

  test "from_node_seed/3 should create a new transaction from the node seeds" do
    Crypto.add_origin_seed("origin_seed")

    assert %Transaction{} =
             Transaction.from_node_seed(:transfer, %Data{
               ledger: %Ledger{
                 uco: %UCO{
                   transfers: [%Transfer{to: "", amount: 10}]
                 }
               }
             })
  end

  test "valid_pending_transaction?/1 should return true when the transaction is valid" do
    Crypto.add_origin_seed("origin_seed")

    assert true =
             Transaction.from_seed("myseed", :transfer, %Data{
               ledger: %Ledger{
                 uco: %UCO{
                   transfers: [%Transfer{to: "", amount: 10}]
                 }
               }
             })
             |> Transaction.valid_pending_transaction?()
  end
end
