defmodule UnirisChain.TransactionTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.Data.Ledger
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer
  alias UnirisCrypto, as: Crypto

  test "new/4 should create a new transaction" do
    origin_keyspairs = [
      {<<0, 195, 84, 216, 212, 203, 243, 221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19,
         136, 12, 49, 220, 138, 27, 238, 216, 110, 230, 9, 61, 135>>,
       <<0, 185, 223, 241, 198, 63, 175, 22, 169, 80, 250, 126, 230, 19, 143, 48, 78, 154, 81, 15,
         70, 197, 195, 14, 144, 116, 203, 211, 27, 237, 151, 18, 174, 195, 84, 216, 212, 203, 243,
         221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19, 136, 12, 49, 220, 138, 27, 238,
         216, 110, 230, 9, 61, 135>>}
    ]

    Crypto.SoftwareImpl.load_origin_keys(origin_keyspairs)

    assert %Transaction{} =
             Transaction.new(:transfer, %Data{
               ledger: %Ledger{
                 uco: %UCO{
                   transfers: [%Transfer{to: "", amount: 10}]
                 }
               }
             })
  end

  test "valid_pending_transaction?/1 should return true when the transaction is valid" do
    origin_keyspairs = [
      {<<0, 195, 84, 216, 212, 203, 243, 221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19,
         136, 12, 49, 220, 138, 27, 238, 216, 110, 230, 9, 61, 135>>,
       <<0, 185, 223, 241, 198, 63, 175, 22, 169, 80, 250, 126, 230, 19, 143, 48, 78, 154, 81, 15,
         70, 197, 195, 14, 144, 116, 203, 211, 27, 237, 151, 18, 174, 195, 84, 216, 212, 203, 243,
         221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19, 136, 12, 49, 220, 138, 27, 238,
         216, 110, 230, 9, 61, 135>>}
    ]

    Crypto.SoftwareImpl.load_origin_keys(origin_keyspairs)

    assert true =
             Transaction.new(:transfer, %Data{
               ledger: %Ledger{
                 uco: %UCO{
                   transfers: [%Transfer{to: "", amount: 10}]
                 }
               }
             })
             |> Transaction.valid_pending_transaction?()
  end
end
