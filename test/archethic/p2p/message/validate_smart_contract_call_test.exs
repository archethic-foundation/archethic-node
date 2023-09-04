defmodule Archethic.P2P.Message.ValidateSmartContractCallTest do
  use ArchethicCase

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  doctest ValidateSmartContractCall

  import Mox
  import ArchethicCase

  describe "serialize/deserialize" do
    test "should work with unnamed action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address()},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        inputs_before: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^msg, <<>>} =
               msg
               |> ValidateSmartContractCall.serialize()
               |> ValidateSmartContractCall.deserialize()
    end

    test "should work with named action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address(), action: "do_it", args: []},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        inputs_before: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^msg, <<>>} =
               msg
               |> ValidateSmartContractCall.serialize()
               |> ValidateSmartContractCall.deserialize()
    end
  end

  describe "process/2" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1000),
        geo_patch: "AAA"
      })

      :ok
    end

    test "should validate smart contract call and return valid message" do
      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             code: ~s"""
             @version 1

             condition triggered_by: transaction, as: [
               content: transaction.timestamp < 5000000000
             ]

             actions triggered_by: transaction do
               Contract.set_content "hello"
             end
             """
           }
         }}
      end)

      incoming_tx = %Transaction{
        data: %TransactionData{
          content: "hola"
        }
      }

      assert %SmartContractCallValidation{valid?: true} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1"},
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should validate smart contract call with named action and return valid message" do
      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             code: ~s"""
             @version 1

             condition triggered_by: transaction, on: upgrade(), as: []
             actions triggered_by: transaction, on: upgrade() do
               Contract.set_code transaction.content
             end
             """
           }
         }}
      end)

      incoming_tx = %Transaction{
        data: %TransactionData{
          content: "hola"
        }
      }

      assert %SmartContractCallValidation{valid?: true} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{
                   address: "@SC1",
                   action: "upgrade",
                   args: []
                 },
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should NOT validate smart contract that does not have a transaction trigger" do
      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             code: ~s"""
             @version 1

             actions triggered_by: datetime, at: 1687874880 do
               Contract.set_content 42
             end
             """
           }
         }}
      end)

      incoming_tx = %Transaction{
        data: %TransactionData{
          content: "hola"
        }
      }

      assert %SmartContractCallValidation{valid?: false} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1"},
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should validate smart contract call and return invalid message" do
      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             code: ~s"""
             @version 1

             condition triggered_by: transaction, as: [
               content: "hola"
             ]

             actions triggered_by: transaction do
               Contract.set_content "hello"
             end
             """
           }
         }}
      end)

      incoming_tx = %Transaction{
        data: %TransactionData{
          content: "hi"
        }
      }

      assert %SmartContractCallValidation{valid?: false} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1"},
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end
  end
end
