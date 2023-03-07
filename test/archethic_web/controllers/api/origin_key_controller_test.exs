defmodule ArchethicWeb.API.OriginKeyControllerTest do
  use ArchethicCase
  use ArchethicWeb.ConnCase

  alias Archethic.{Crypto, P2P, P2P.Node, SharedSecrets}
  alias Archethic.{SharedSecrets.MemTables.OriginKeyLookup, P2P.Message.Ok}

  import ArchethicCase, only: [setup_before_send_tx: 0]

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

    setup_before_send_tx()
    :ok
  end

  describe "origin_key/2" do
    test "should send invalid key size", %{conn: conn} do
      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: "0001540315",
          certificate: ""
        })

      assert %{"status" => "invalid", "errors" => %{"origin_public_key" => ["invalid key size"]}} =
               json_response(conn, 400)
    end

    test "should send json secret values response when public key is found in owner transactions",
         %{conn: conn} do
      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, %Ok{}}
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

    test "should send Origin Public Key already exists.",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, %Ok{}}
      end)

      {public_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      OriginKeyLookup.add_public_key(:software, public_key)
      certificate = Crypto.get_key_certificate(public_key)

      assert true == SharedSecrets.has_origin_public_key?(public_key)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: Base.encode16(public_key),
          certificate: certificate
        })

      assert %{"status" => "invalid", "errors" => %{"origin_public_key" => ["Already Exists"]}} =
               json_response(conn, 400)
    end

    test "should accept, Origin Public Key does not exists",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, %Ok{}}
      end)

      {public_key, _} = Crypto.derive_keypair("does_not_have_origin_public_key2", 0)
      assert false == SharedSecrets.has_origin_public_key?(public_key)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: Base.encode16(public_key),
          certificate: ""
        })

      assert %{
               "status" => "pending"
             } = json_response(conn, 201)
    end
  end

  describe "validate_certificate/2" do
    test "should accept certificate, with Origin: software|:on_chain_wallet, with empty Certificate",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, %Ok{}}
      end)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key:
            _on_chain_wallet_origin_public_key =
              Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          certificate: ""
        })

      assert %{
               "status" => "pending"
             } = json_response(conn, 201)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key:
            _software_public_key =
              Base.encode16(<<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>),
          certificate: ""
        })

      assert %{
               "status" => "pending"
             } = json_response(conn, 201)
    end

    test "should send Invalid Certificate, Erroneous certifcate/Root_CA_Public_key ",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, %Ok{}}
      end)

      public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      certificate = <<0::8, 5::8, :crypto.strong_rand_bytes(32)::binary>>

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: _on_chain_wallet_origin_public_key = Base.encode16(public_key),
          certificate: Base.encode16(certificate)
        })

      assert %{
               "status" => "invalid",
               "errors" => %{"certificate" => ["Invalid Certificate"]}
             } = json_response(conn, 400)

      public_key = <<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: _software_public_key = Base.encode16(public_key),
          certificate: Base.encode16(certificate)
        })

      assert %{"status" => "invalid", "errors" => %{"certificate" => ["Invalid Certificate"]}} =
               json_response(conn, 400)
    end

    test "should return certificate error, with Random Certificate Value",
         %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        {:ok, %Ok{}}
      end)

      public_key = <<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: _software_public_key = Base.encode16(public_key),
          certificate: "random certificate value"
        })

      assert %{"status" => "invalid", "errors" => %{"certificate" => ["must be hexadecimal"]}} =
               json_response(conn, 400)
    end

    test "should send Certificate size exceeds limit",
         %{conn: conn} do
      # due to a empty root_ca_key it will reject valid yet containing large Random Value
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        %Ok{}
      end)

      public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      certificate = <<0::8, 0::8, :crypto.strong_rand_bytes(10_000)::binary>>

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: Base.encode16(public_key),
          certificate: Base.encode16(certificate)
        })

      assert %{
               "errors" => %{"certificate" => ["Certificate size exceeds limit"]},
               "status" => "invalid"
             } = json_response(conn, 400)
    end

    test "Should get InValid Certificate, With ed25519", %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, _, _ ->
        %Ok{}
      end)

      {ca_public_key, ca_private_key} = :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")

      {pbk = <<_curve_id::8, _origin_id::8, public_key_bin::binary>>, _} =
        Crypto.derive_keypair("random-test-key", 0)

      refute SharedSecrets.has_origin_public_key?(pbk)

      signature = Crypto.ECDSA.sign(:secp256r1, ca_private_key, public_key_bin)
      # :secp256r1, root_ca_key, key, certificate)
      assert Crypto.ECDSA.verify?(:secp256r1, ca_public_key, public_key_bin, signature)

      conn =
        post(conn, "/api/origin_key", %{
          origin_public_key: Base.encode16(pbk),
          certificate: Base.encode16(signature)
        })

      assert %{
               "errors" => %{"certificate" => ["Invalid Certificate"]},
               "status" => "invalid"
             } = json_response(conn, 400)
    end
  end
end
