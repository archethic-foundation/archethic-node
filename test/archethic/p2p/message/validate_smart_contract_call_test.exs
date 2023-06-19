defmodule Archethic.P2P.Message.ValidateSmartContractCallTest do
  use ArchethicCase

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  doctest ValidateSmartContractCall

  import Mox

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

             condition transaction: [
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
          content: "hola"
        },
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert %SmartContractCallValidation{valid?: true} =
               %ValidateSmartContractCall{
                 contract_address: "@SC1",
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

             condition transaction: [
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
        },
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert %SmartContractCallValidation{valid?: false} =
               %ValidateSmartContractCall{
                 contract_address: "@SC1",
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end
  end
end
