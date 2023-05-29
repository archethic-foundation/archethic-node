defmodule Archethic.P2P.Message.ValidateSmartContractCallTest do
  use ArchethicCase

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetContractCalls
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.ValidateSmartContractCall

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  doctest ValidateSmartContractCall

  import Mox

  describe "process/1" do
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

      MockClient
      |> expect(:send_message, fn _, %GetContractCalls{}, _ ->
        {:ok, %TransactionList{transactions: []}}
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
               |> ValidateSmartContractCall.process()
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

      MockClient
      |> expect(:send_message, fn _, %GetContractCalls{}, _ ->
        {:ok, %TransactionList{transactions: []}}
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
               |> ValidateSmartContractCall.process()
    end

    test "should validate smart contract call based on the inputs" do
      MockClient
      |> stub(:send_message, fn _, %GetContractCalls{}, _ ->
        %Transaction{
          data: %TransactionData{},
          validation_stamp: %ValidationStamp{timestamp: ~U[2023-05-23 15:30:27Z]}
        }

        transactions =
          Enum.map(1..9, fn i ->
            vote =
              if rem(i, 3) == 0 do
                "X"
              else
                "Y"
              end

            %Transaction{
              data: %TransactionData{
                content: "#{vote}"
              },
              validation_stamp: %ValidationStamp{
                timestamp: ~U[2023-05-23 15:30:27Z] |> DateTime.add(i)
              }
            }
          end)

        {:ok, %TransactionList{transactions: transactions}}
      end)

      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             code: ~S"""
             @version 1

             condition transaction: [
               # Limit date: 2023-05-23 15:47:35
               timestamp: Time.now() < 1684856867,
               content: Regex.match?("^[X|Y]$")
             ]

             actions triggered_by: transaction do

               inputs = Contract.get_calls()
               if List.size(inputs) > 9 do
                 vote_for_x = 0
                 vote_for_y = 0

                 for input in inputs do
                     if Regex.match?(input.content, "X") do
                       vote_for_x = vote_for_x + 1
                     else
                       vote_for_y = vote_for_y + 1
                     end
                 end
                 Contract.set_content "Votes results: X: #{String.from_number(vote_for_x)}; Y: #{String.from_number(vote_for_y)}"
               end
             end
             """
           }
         }}
      end)

      incoming_tx = %Transaction{
        data: %TransactionData{
          content: "X"
        },
        validation_stamp: %ValidationStamp{timestamp: ~U[2023-05-23 15:30:36Z]}
      }

      assert %SmartContractCallValidation{valid?: true} =
               %ValidateSmartContractCall{
                 contract_address: "@SC1",
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process()
    end
  end
end
