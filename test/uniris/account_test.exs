defmodule Uniris.AccountTest do
  use ExUnit.Case

  alias Uniris.Account
  alias Uniris.Account.MemTables.NFTLedger
  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

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
          amount: 3.0,
          type: :UCO
        },
        ~U[2021-03-05 13:41:34Z]
      )

      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Tom10",
          amount: 1.0,
          type: :UCO
        },
        ~U[2021-03-05 13:41:34Z]
      )

      NFTLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Charlie2",
          amount: 100.0,
          type: {:NFT, "@CharlieNFT"}
        },
        ~U[2021-03-05 13:41:34Z]
      )

      assert %{uco: 4.0, nft: %{"@CharlieNFT" => 100}} == Account.get_balance("@Alice2")
    end

    test "should return 0 when no unspent outputs associated" do
      assert %{uco: 0.0, nft: %{}} == Account.get_balance("@Alice2")
    end

    test "should return 0 when all the unspent outputs have been spent" do
      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{from: "@Bob3", amount: 3.0},
        ~U[2021-03-05 13:41:34Z]
      )

      UCOLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{from: "@Tom10", amount: 1.0},
        ~U[2021-03-05 13:41:34Z]
      )

      NFTLedger.add_unspent_output(
        "@Alice2",
        %UnspentOutput{
          from: "@Charlie2",
          amount: 100.0,
          type: {:NFT, "@CharlieNFT"}
        },
        ~U[2021-03-05 13:41:34Z]
      )

      UCOLedger.spend_all_unspent_outputs("@Alice2")
      NFTLedger.spend_all_unspent_outputs("@Alice2")

      assert %{uco: 0.0, nft: %{}} == Account.get_balance("@Alice2")
    end
  end
end
