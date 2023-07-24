defmodule ArchethicWeb.API.JsonRPC.Methods.AddOriginKeyTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Method.AddOriginKey

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Message.Ok

  alias Archethic.SelfRepair.NetworkView

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

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
    test "should send bad_request response for invalid transaction body" do
      assert {:error, %{origin_public_key: ["can't be blank"]}} =
               AddOriginKey.validate_params(%{})
    end
  end

  describe "execute" do
    test "should create a new origin transaction" do
      me = self()

      MockClient
      |> expect(:send_message, fn _, %StartMining{transaction: tx}, _ ->
        send(me, {:transaction_sent, tx})
        {:ok, %Ok{}}
      end)

      {public_key, _} = Crypto.derive_keypair(:crypto.strong_rand_bytes(32), 0)
      OriginKeyLookup.add_public_key(:software, public_key)
      certificate = Crypto.get_key_certificate(public_key)

      assert true == SharedSecrets.has_origin_public_key?(public_key)

      tx_content = <<public_key::binary, byte_size(certificate)::16, certificate::binary>>

      params = %{
        origin_public_key: public_key,
        certificate: certificate
      }

      AddOriginKey.execute(params)

      assert_receive {:transaction_sent, tx}
      assert %Transaction{type: :origin, data: %TransactionData{content: ^tx_content}} = tx
    end
  end
end
