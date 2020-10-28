defmodule Uniris.Account.MemTablesLoaderTest do
  use ExUnit.Case

  alias Uniris.Account.MemTables.UCOLedger
  alias Uniris.Account.MemTablesLoader

  alias Uniris.Bootstrap

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
      :ok
    end

    test "should distribute unspent outputs" do
      assert :ok = MemTablesLoader.load_transaction(create_transaction())

      [
        %UnspentOutput{from: "@Charlie3", amount: 19.0},
        %UnspentOutput{from: "@Alice2", amount: 2.0}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 1.303}] =
        UCOLedger.get_unspent_outputs(Crypto.hash("@Node2"))

      [%UnspentOutput{from: "@Charlie3", amount: 34.0}] = UCOLedger.get_unspent_outputs("@Tom4")
    end
  end

  describe "start_link/1" do
    setup do
      start_supervised!(UCOLedger)

      MockDB
      |> stub(:list_transactions, fn _fields -> [create_transaction()] end)

      :ok
    end

    test "should initiate the genesis address allocation" do
      assert {:ok, _} = MemTablesLoader.start_link()

      assert [%UnspentOutput{amount: 1.0e10}] =
               UCOLedger.get_unspent_outputs(Bootstrap.genesis_unspent_output_address())
    end

    test "should query DB to load all the transactions" do
      assert {:ok, _} = MemTablesLoader.start_link()

      [
        %UnspentOutput{from: "@Charlie3", amount: 19.0},
        %UnspentOutput{from: "@Alice2", amount: 2.0}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 1.303}] =
        UCOLedger.get_unspent_outputs(Crypto.hash("@Node2"))

      [%UnspentOutput{from: "@Charlie3", amount: 34.0}] = UCOLedger.get_unspent_outputs("@Tom4")
    end
  end

  defp create_transaction do
    %Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        ledger_operations: %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Tom4", amount: 34.0}
          ],
          node_movements: [%NodeMovement{to: "@Node2", amount: 1.303, roles: []}],
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 2.0
            },
            %UnspentOutput{from: "@Charlie3", amount: 19.0}
          ]
        }
      }
    }
  end
end
