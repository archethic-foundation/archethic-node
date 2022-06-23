defmodule Archethic.Account.MemTablesLoaderTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTablesLoader

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: "NodeKey",
      last_public_key: "NodeKey",
      reward_address: "@NodeKey",
      ip: {127, 0, 0, 1},
      port: 3000,
      geo_patch: "AAA"
    })

    :ok
  end

  describe "load_transaction/1" do
    test "should distribute unspent outputs" do
      assert :ok = MemTablesLoader.load_transaction(create_transaction())

      [
        %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO},
        %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 3_400_000_000}] =
        UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0}
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  describe "start_link/1" do
    setup do
      MockDB
      |> stub(:list_transactions, fn _fields -> [create_transaction()] end)

      :ok
    end

    test "should query DB to load all the transactions" do
      assert {:ok, _} = MemTablesLoader.start_link()

      [
        %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO},
        %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 3_400_000_000, type: :UCO}] =
        UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0}
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  defp create_transaction do
    %Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        timestamp: DateTime.utc_now(),
        ledger_operations: %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Tom4", amount: 3_400_000_000, type: :UCO},
            %TransactionMovement{
              to: "@Bob3",
              amount: 1_000_000_000,
              type: {:token, "@CharlieToken", 0}
            }
          ],
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 200_000_000,
              type: :UCO
            },
            %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO}
          ]
        }
      }
    }
  end
end
