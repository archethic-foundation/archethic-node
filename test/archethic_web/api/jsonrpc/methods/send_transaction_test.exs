defmodule ArchethicWeb.API.JsonRPC.Methods.SendTransactionTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Method.SendTransaction

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Message.TransactionSummaryMessage

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.TransactionFactory

  alias Archethic.SelfRepair.NetworkView

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    start_supervised!(NetworkView)

    :ok
  end

  describe "validate_params" do
    test "should send error when transaction key is missing" do
      assert {:error, %{"transaction" => "Is required"}} = SendTransaction.validate_params(%{})
    end

    test "should send bad_request response for invalid transaction body" do
      assert {:error,
              %{
                "#" =>
                  "Required properties version, address, type, previousPublicKey, previousSignature, originSignature, data were not present."
              }} = SendTransaction.validate_params(%{"transaction" => %{}})
    end
  end

  describe "execute" do
    test "should send the transaction and respond the state of the transaction" do
      tx = %Transaction{address: address} = TransactionFactory.create_non_valided_transaction()
      address = Base.encode16(address)

      MockClient
      |> expect(:send_message, fn _, %GetTransactionSummary{}, _ -> {:ok, %NotFound{}} end)
      |> expect(:send_message, fn _, %StartMining{transaction: ^tx}, _ -> {:ok, %Ok{}} end)

      assert {:ok, %{status: "pending", transaction_address: ^address}} =
               SendTransaction.execute(tx)
    end

    test "should not send the transaction if it already exists" do
      tx = %Transaction{address: address} = TransactionFactory.create_non_valided_transaction()

      MockClient
      |> expect(:send_message, fn _, %GetTransactionSummary{}, _ ->
        {:ok,
         %TransactionSummaryMessage{transaction_summary: %TransactionSummary{address: address}}}
      end)
      |> expect(:send_message, 0, fn _, %StartMining{transaction: ^tx}, _ -> {:ok, %Ok{}} end)

      assert {:error, :transaction_exists, _} = SendTransaction.execute(tx)
    end
  end
end
