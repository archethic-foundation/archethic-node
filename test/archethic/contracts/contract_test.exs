defmodule Archethic.Contracts.ContractTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Contract

  alias Archethic.TransactionChain.TransactionData.Recipient

  describe "get_trigger_for_recipient/2" do
    test "should return trigger" do
      assert {:transaction, "vote", 1} =
               Contract.get_trigger_for_recipient(%Recipient{
                 address: random_address(),
                 action: "vote",
                 args: ["Julio"]
               })
    end

    test "should return {:transaction, nil, nil} when no action nor args" do
      assert {:transaction, nil, nil} ==
               Contract.get_trigger_for_recipient(%Recipient{address: random_address()})
    end
  end
end
