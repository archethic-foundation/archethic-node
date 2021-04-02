defmodule Uniris.TransactionChain.MemTablesLoaderTest do
  use ExUnit.Case

  alias Uniris.Crypto

  alias Uniris.TransactionChain.MemTables.PendingLedger
  alias Uniris.TransactionChain.MemTablesLoader
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

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
                 timestamp: DateTime.utc_now(),
                 previous_public_key: "CodeProp0",
                 data: %TransactionData{},
                 type: :code_proposal
               }
               |> MemTablesLoader.load_transaction()

      assert ["@CodeProp1"] = PendingLedger.list_signatures("@CodeProp1")
    end

    test "should track pending transaction when a smart contract requires conditions is loaded" do
      assert :ok =
               %Transaction{
                 address: "@Contract2",
                 timestamp: DateTime.utc_now(),
                 previous_public_key: "Contract1",
                 data: %TransactionData{
                   code: """
                   condition transaction: regex_match?(content, \"hello\")
                   actions triggered_by: transaction do end
                   """
                 },
                 type: :transfer
               }
               |> MemTablesLoader.load_transaction()

      assert ["@Contract2"] = PendingLedger.list_signatures("@Contract2")
    end

    test "should track recipients to add signature to pending transaction" do
      assert :ok =
               %Transaction{
                 address: "@CodeProp1",
                 timestamp: DateTime.utc_now(),
                 previous_public_key: "CodeProp0",
                 data: %TransactionData{},
                 type: :code_proposal
               }
               |> MemTablesLoader.load_transaction()

      assert :ok =
               %Transaction{
                 address: "@CodeApproval1",
                 timestamp: DateTime.utc_now(),
                 previous_public_key: "CodeApproval0",
                 data: %TransactionData{
                   recipients: ["@CodeProp1"]
                 },
                 type: :code_approval
               }
               |> MemTablesLoader.load_transaction()

      assert ["@CodeProp1", "@CodeApproval1"] = PendingLedger.list_signatures("@CodeProp1")
    end
  end

  describe "start_link/1" do
    test "should load from database the transaction to index" do
      MockDB
      |> stub(:list_transactions, fn _ ->
        [
          %Transaction{
            address: Crypto.hash("Alice2"),
            timestamp: DateTime.utc_now(),
            previous_public_key: "Alice1",
            data: %TransactionData{},
            type: :transfer
          },
          %Transaction{
            address: Crypto.hash("Alice1"),
            timestamp: DateTime.utc_now() |> DateTime.add(-10),
            previous_public_key: "Alice0",
            data: %TransactionData{},
            type: :transfer
          },
          %Transaction{
            address: "@CodeProp1",
            timestamp: DateTime.utc_now(),
            previous_public_key: "CodeProp0",
            data: %TransactionData{},
            type: :code_proposal
          },
          %Transaction{
            address: "@CodeApproval1",
            timestamp: DateTime.utc_now(),
            previous_public_key: "CodeApproval0",
            data: %TransactionData{
              recipients: ["@CodeProp1"]
            },
            type: :code_approval
          }
        ]
      end)

      assert {:ok, _} = MemTablesLoader.start_link()

      assert ["@CodeProp1", "@CodeApproval1"] == PendingLedger.list_signatures("@CodeProp1")
    end
  end
end
