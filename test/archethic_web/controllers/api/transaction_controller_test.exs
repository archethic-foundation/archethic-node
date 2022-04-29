defmodule ArchEthicWeb.API.TransactionControllerTest do
  use ArchEthicCase
  use ArchEthicWeb.ConnCase

  alias ArchEthic.OracleChain.MemTable
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  import Mox

  alias ArchEthic.SharedSecrets
  alias ArchEthic.TransactionChain

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

  describe "transaction_fee/2" do
    test "should send ok response and return fee for valid transaction body", %{conn: conn} do
      MemTable.add_oracle_data("uco", %{"eur" => 0.2, "usd" => 0.2}, DateTime.utc_now())

      conn =
        post(conn, "/api/transaction_fee", %{
          "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
          "data" => %{
            "ledger" => %{
              "nft" => %{"transfers" => []},
              "uco" => %{
                "transfers" => [
                  %{
                    "amount" => trunc(100_000_000),
                    "to" => "000098fe10e8633bce19c59a40a089731c1f72b097c5a8f7dc71a37eb26913aa4f80"
                  }
                ]
              }
            }
          },
          "originSignature" =>
            "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
          "previousPublicKey" =>
            "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
          "previousSignature" =>
            "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
          "type" => "transfer",
          "version" => 1
        })

      assert %{
               "fee" => 0.50001325,
               "rates" => %{
                 "eur" => 0.2,
                 "usd" => 0.2
               }
             } = json_response(conn, 200)
    end

    test "should send bad_request response for invalid transaction body", %{conn: conn} do
      conn = post(conn, "/api/transaction_fee", %{})

      assert %{
               "errors" => %{
                 "address" => [
                   "can't be blank"
                 ],
                 "data" => [
                   "can't be blank"
                 ],
                 "originSignature" => [
                   "can't be blank"
                 ],
                 "previousPublicKey" => [
                   "can't be blank"
                 ],
                 "previousSignature" => [
                   "can't be blank"
                 ],
                 "type" => [
                   "can't be blank"
                 ],
                 "version" => [
                   "can't be blank"
                 ]
               },
               "status" => "invalid"
             } = json_response(conn, 400)
    end
  end

  describe "origin_key/2" do
    test "should send not_found response for invalid params", %{conn: conn} do
      conn = get(conn, "/api/origin_key/invalid")

      assert "[]" = response(conn, 404)
    end

    test "should send not_found response when public key isn't found in owner transactions", %{
      conn: conn
    } do
      MockDB
      |> stub(:get_transaction, fn _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             ownerships: [
               %Ownership{
                 secret: Base.decode16!("0001AAAAAA"),
                 authorized_keys: %{Base.decode16!("0001BBBBBB") => Base.decode16!("0001CCCCCC")}
               }
             ]
           }
         }}
      end)

      MockDB
      |> stub(:get_last_chain_address, fn _ ->
        Base.decode16!("0001DDDDDD")
      end)

      conn = get(conn, "/api/origin_key/0001FFFFFF")

      assert "[]" = response(conn, 404)
    end

    test "should send json secret values response when public key is found in owner transactions",
         %{conn: conn} do
      MockDB
      |> stub(:get_transaction, fn _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             ownerships: [
               %Ownership{
                 secret: Base.decode16!("0001AAAAAA"),
                 authorized_keys: %{Base.decode16!("0001BBBBBB") => Base.decode16!("0001CCCCCC")}
               }
             ]
           }
         }}
      end)

      MockDB
      |> stub(:get_last_chain_address, fn _ ->
        Base.decode16!("0001DDDDDD")
      end)

      conn = get(conn, "/api/origin_key/0001BBBBBB")

      assert %{
               "encrypted_origin_private_key" => "0001AAAAAA",
               "encrypted_secret_key" => "0001CCCCCC"
             } = json_response(conn, 200)
    end
  end
end
