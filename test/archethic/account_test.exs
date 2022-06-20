defmodule Archethic.AccountTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.Account
  alias Archethic.Account.MemTables.NFTLedger
  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  describe "get_balance/1" do
    setup do
      start_supervised!(UCOLedger)
      start_supervised!(NFTLedger)
      :ok
    end

    test "should return the sum of unspent outputs amounts" do
      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Bob3",
          amount: 300_000_000,
          type: :UCO
        },
        ~U[2021-03-05 13:41:34Z]
      )

      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Tom10",
          amount: 100_000_000,
          type: :UCO
        },
        ~U[2021-03-05 13:41:34Z]
      )

      NFTLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Charlie2",
          amount: 10_000_000_000,
          type: {:NFT, "@CharlieNFT", 0}
        },
        ~U[2021-03-05 13:41:34Z]
      )

      assert %{uco: 400_000_000, nft: %{{"@CharlieNFT", 0} => 10_000_000_000}} ==
               Account.get_balance("@Alice2")
    end

    test "should return 0 when no unspent outputs associated" do
      assert %{uco: 0, nft: %{}} == Account.get_balance("@Alice2")
    end

    test "should return 0 when all the unspent outputs have been spent" do
      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{from: "@Bob3", amount: 300_000_000},
        ~U[2021-03-05 13:41:34Z]
      )

      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{from: "@Tom10", amount: 100_000_000},
        ~U[2021-03-05 13:41:34Z]
      )

      NFTLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Charlie2",
          amount: 10_000_000_000,
          type: {:NFT, "@CharlieNFT", 0}
        },
        ~U[2021-03-05 13:41:34Z]
      )

      UCOLedger.spend_all_unspent_outputs("@Alice2")
      NFTLedger.spend_all_unspent_outputs("@Alice2")

      assert %{uco: 0, nft: %{}} == Account.get_balance("@Alice2")
    end
  end
end
