defmodule ArchEthicWeb.API.OriginKeyControllerTest do
  use ArchEthicCase
  use ArchEthicWeb.ConnCase

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

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

    :ok
  end

  describe "origin_key/2" do
    test "should send not_found response for invalid params", %{conn: conn} do
      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: "0001540315"
        })

      assert %{
               "error" => "Invalid public key"
             } = json_response(conn, 400)
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

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key:
            "00015403152aeb59b1b584d77c8f326031815674afeade8cba25f18f02737d599c39"
        })

      assert %{
               "error" => "Public key not found"
             } = json_response(conn, 404)
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
                 authorized_keys: %{
                   Base.decode16!(
                     "00015403152aeb59b1b584d77c8f326031815674afeade8cba25f18f02737d599c39",
                     case: :mixed
                   ) => Base.decode16!("0001CCCCCC")
                 }
               }
             ]
           }
         }}
      end)

      MockDB
      |> stub(:get_last_chain_address, fn _ ->
        Base.decode16!("0001DDDDDD")
      end)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key:
            "00015403152aeb59b1b584d77c8f326031815674afeade8cba25f18f02737d599c39"
        })

      assert %{
               "encrypted_origin_private_keys" => "0001AAAAAA",
               "encrypted_secret_key" => "0001CCCCCC"
             } = json_response(conn, 200)
    end
  end
end
