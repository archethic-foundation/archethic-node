defmodule ArchethicWeb.API.OriginKeyControllerTest do
  use ArchethicCase
  use ArchethicWeb.ConnCase

  alias Archethic.{Crypto, P2P, P2P.Node, SharedSecrets, SharedSecrets.MemTables.OriginKeyLookup}

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

    OriginKeyLookup.start_link()

    :ok
  end

  describe "origin_key/2" do
    test "should send not_found response for invalid params", %{conn: conn} do
      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: "0001540315",
          certificate: ""
        })

      assert %{
               "status" => "error - invalid public key"
             } = json_response(conn, 400)
    end

    test "should send json secret values response when public key is found in owner transactions",
         %{conn: conn} do
      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, :ok}
      end)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key:
            "00015403152aeb59b1b584d77c8f326031815674afeade8cba25f18f02737d599c39",
          certificate: ""
        })

      assert %{
               "status" => "pending"
             } = json_response(conn, 201)
    end
  end

  describe "Origin Key Lookup Test" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      OriginKeyLookup.start_link([])

      :ok
    end

    test "should not accept origin transactions when the Origin Public Key already exists.",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, :ok}
      end)

      {public_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      OriginKeyLookup.add_public_key(:software, public_key)
      certificate = Crypto.get_key_certificate(public_key)

      assert true == SharedSecrets.has_origin_public_key?(public_key)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: public_key |> Base.encode16(),
          certificate: certificate |> Base.encode16()
        })

      assert %{
               "status" => "error - public key exists"
             } = json_response(conn, 400)
    end

    test "should accept origin transactions when the Origin Public Key does not exists",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, :ok}
      end)

      {public_key, _} = Crypto.derive_keypair("does_not_have_origin_public_key2", 0)
      certificate = Crypto.get_key_certificate(public_key)

      assert false == SharedSecrets.has_origin_public_key?(public_key)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: public_key |> Base.encode16(),
          certificate: certificate |> Base.encode16()
        })

      assert %{
               "status" => "pending"
             } = json_response(conn, 201)
    end
  end
end
