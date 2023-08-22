defmodule ArchethicWeb.API.JsonRPC.Methods.EstimateTransactionFeeTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Method.EstimateTransactionFee

  alias Archethic.Crypto

  alias Archethic.OracleChain
  alias Archethic.OracleChain.MemTable

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionFactory

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

    :ok
  end

  describe "validate_params" do
    test "should send error when transaction key is missing" do
      assert {:error,
              %{
                transaction: [
                  "is required"
                ]
              }} = EstimateTransactionFee.validate_params(%{})
    end

    test "should send bad_request response for invalid transaction body" do
      assert {:error,
              %{
                address: [
                  "can't be blank"
                ],
                data: [
                  "can't be blank"
                ],
                originSignature: [
                  "can't be blank"
                ],
                previousPublicKey: [
                  "can't be blank"
                ],
                previousSignature: [
                  "can't be blank"
                ],
                type: [
                  "can't be blank"
                ],
                version: [
                  "can't be blank"
                ]
              }} = EstimateTransactionFee.validate_params(%{"transaction" => %{}})
    end
  end

  describe "execute" do
    test "should send ok response and return fee for valid transaction body" do
      previous_oracle_time =
        DateTime.utc_now()
        |> OracleChain.get_last_scheduling_date()
        |> OracleChain.get_last_scheduling_date()

      MemTable.add_oracle_data("uco", %{"eur" => 0.2, "usd" => 0.2}, previous_oracle_time)

      tx = TransactionFactory.create_non_valided_transaction()

      assert {:ok,
              %{
                "fee" => 5_000_080,
                "rates" => %{
                  "eur" => 0.2,
                  "usd" => 0.2
                }
              }} = EstimateTransactionFee.execute(tx)
    end
  end
end
