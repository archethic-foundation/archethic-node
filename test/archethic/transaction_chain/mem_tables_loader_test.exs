defmodule Archethic.TransactionChain.MemTablesLoaderTest do
  use ExUnit.Case

  alias Archethic.Crypto

  alias Archethic.TransactionChain.MemTables.PendingLedger
  alias Archethic.TransactionChain.MemTablesLoader
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    start_supervised!(PendingLedger)
    :ok
  end

  describe "load_transaction/1" do
    test "should track pending transaction when a code proposal transaction is loaded" do
      assert :ok =
               %Transaction{
                 address: "@CodeProp1",
                 previous_public_key: "CodeProp0",
                 data: %TransactionData{},
                 type: :code_proposal,
                 validation_stamp: %ValidationStamp{
                   timestamp: DateTime.utc_now()
                 }
               }
               |> MemTablesLoader.load_transaction()

      assert ["@CodeProp1"] = PendingLedger.get_signatures("@CodeProp1")
    end

    test "should track pending transaction when a smart contract requires conditions is loaded" do
      assert :ok =
               %Transaction{
                 address: "@Contract2",
                 previous_public_key: "Contract1",
                 data: %TransactionData{
                   code: """
                   condition inherit: []

                   condition transaction: [
                     content: regex_match?(\"hello\")
                   ]

                   actions triggered_by: transaction do end
                   """
                 },
                 type: :transfer,
                 validation_stamp: %ValidationStamp{
                   timestamp: DateTime.utc_now()
                 }
               }
               |> MemTablesLoader.load_transaction()

      assert ["@Contract2"] = PendingLedger.get_signatures("@Contract2")
    end

    test "should track recipients to add signature to pending transaction" do
      assert :ok =
               %Transaction{
                 address: "@CodeProp1",
                 previous_public_key: "CodeProp0",
                 data: %TransactionData{},
                 type: :code_proposal,
                 validation_stamp: %ValidationStamp{
                   timestamp: DateTime.utc_now()
                 }
               }
               |> MemTablesLoader.load_transaction()

      assert :ok =
               %Transaction{
                 address: "@CodeApproval1",
                 previous_public_key: "CodeApproval0",
                 data: %TransactionData{
                   recipients: [%Recipient{address: "@CodeProp1"}]
                 },
                 type: :code_approval,
                 validation_stamp: %ValidationStamp{
                   timestamp: DateTime.utc_now()
                 }
               }
               |> MemTablesLoader.load_transaction()

      assert ["@CodeProp1", "@CodeApproval1"] = PendingLedger.get_signatures("@CodeProp1")
    end
  end

  describe "start_link/1" do
    test "should load from database the transaction to index" do
      MockDB
      |> stub(:list_transactions, fn _ ->
        [
          %Transaction{
            address: Crypto.hash("Alice2"),
            previous_public_key: "Alice1",
            data: %TransactionData{},
            type: :transfer,
            validation_stamp: %ValidationStamp{
              timestamp: DateTime.utc_now()
            }
          },
          %Transaction{
            address: Crypto.hash("Alice1"),
            previous_public_key: "Alice0",
            data: %TransactionData{},
            type: :transfer,
            validation_stamp: %ValidationStamp{
              timestamp: DateTime.utc_now() |> DateTime.add(-10)
            }
          },
          %Transaction{
            address: "@CodeProp1",
            previous_public_key: "CodeProp0",
            data: %TransactionData{},
            type: :code_proposal,
            validation_stamp: %ValidationStamp{
              timestamp: DateTime.utc_now()
            }
          },
          %Transaction{
            address: "@CodeApproval1",
            previous_public_key: "CodeApproval0",
            data: %TransactionData{
              recipients: [%Recipient{address: "@CodeProp1"}]
            },
            type: :code_approval,
            validation_stamp: %ValidationStamp{
              timestamp: DateTime.utc_now()
            }
          }
        ]
      end)

      assert {:ok, _} = MemTablesLoader.start_link()

      assert ["@CodeProp1", "@CodeApproval1"] == PendingLedger.get_signatures("@CodeProp1")
    end
  end
end
