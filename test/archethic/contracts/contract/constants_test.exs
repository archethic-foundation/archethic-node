defmodule Archethic.Contracts.ContractConstantsTest do
  use ArchethicCase

  alias Archethic.TransactionFactory
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Contracts.ContractConstants

  test "from_transaction/1 should return a map" do
    tx = TransactionFactory.create_valid_transaction()

    constant =
      tx
      |> ContractConstants.from_transaction()

    assert %{"type" => "transfer"} = constant
  end

  test "to_transaction/1 should return a transaction" do
    tx = TransactionFactory.create_valid_transaction()

    # from_transaction/1 is a destructive function, we can't check
    # that result is equal to tx
    assert %Transaction{type: :transfer} =
             tx
             |> ContractConstants.from_transaction()
             |> ContractConstants.to_transaction()
  end
end
