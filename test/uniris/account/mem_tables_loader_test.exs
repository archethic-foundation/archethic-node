defmodule Uniris.Account.MemTablesLoaderTest do
  use ExUnit.Case

  alias Uniris.Account.MemTables.NFTLedger
  alias Uniris.Account.MemTables.UCOLedger
  alias Uniris.Account.MemTablesLoader

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  describe "load_transaction/1" do
    setup do
      start_supervised!(UCOLedger)
      start_supervised!(NFTLedger)
      :ok
    end

    test "should distribute unspent outputs" do
      assert :ok = MemTablesLoader.load_transaction(create_transaction())

      [
        %UnspentOutput{from: "@Charlie3", amount: 19.0, type: :UCO},
        %UnspentOutput{from: "@Alice2", amount: 2.0, type: :UCO}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 1.303, type: :UCO}] =
        UCOLedger.get_unspent_outputs(Crypto.hash("@Node2"))

      [%UnspentOutput{from: "@Charlie3", amount: 34.0}] = UCOLedger.get_unspent_outputs("@Tom4")

      assert [%UnspentOutput{from: "@Charlie3", amount: 10.0, type: {:NFT, "@CharlieNFT"}}] =
               NFTLedger.get_unspent_outputs("@Bob3")
    end
  end

  describe "start_link/1" do
    setup do
      start_supervised!(UCOLedger)
      start_supervised!(NFTLedger)

      MockDB
      |> stub(:list_transactions, fn _fields -> [create_transaction()] end)

      :ok
    end

    test "should query DB to load all the transactions" do
      assert {:ok, _} = MemTablesLoader.start_link()

      [
        %UnspentOutput{from: "@Charlie3", amount: 19.0, type: :UCO},
        %UnspentOutput{from: "@Alice2", amount: 2.0, type: :UCO}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 1.303, type: :UCO}] =
        UCOLedger.get_unspent_outputs(Crypto.hash("@Node2"))

      [%UnspentOutput{from: "@Charlie3", amount: 34.0, type: :UCO}] =
        UCOLedger.get_unspent_outputs("@Tom4")

      assert [%UnspentOutput{from: "@Charlie3", amount: 10.0, type: {:NFT, "@CharlieNFT"}}] =
               NFTLedger.get_unspent_outputs("@Bob3")
    end
  end

  defp create_transaction do
    %Transaction{
      address: "@Charlie3",
      timestamp: DateTime.utc_now(),
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        ledger_operations: %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Tom4", amount: 34.0, type: :UCO},
            %TransactionMovement{to: "@Bob3", amount: 10.0, type: {:NFT, "@CharlieNFT"}}
          ],
          node_movements: [%NodeMovement{to: "@Node2", amount: 1.303, roles: []}],
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 2.0,
              type: :UCO
            },
            %UnspentOutput{from: "@Charlie3", amount: 19.0, type: :UCO}
          ]
        }
      }
    }
  end
end
