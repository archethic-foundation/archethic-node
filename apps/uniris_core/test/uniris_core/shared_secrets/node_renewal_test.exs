defmodule UnirisCore.SharedSecrets.NodeRenewalTest do
  use UnirisCoreCase

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Crypto
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.SharedSecrets.NodeRenewal

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    %{pid: start_supervised!({NodeRenewal, interval: 1000, trigger_offset: 800})}
  end

  test "handle_info should accept :renew message to create a new transaction with new authorized nodes",
       %{pid: pid} do
    me = self()

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        {:start_mining, tx, _, _} ->
          send(me, tx)
      end
    end)

    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: pub,
      first_public_key: pub,
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true
    })

    send(pid, :renew)

    receive do
      %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{keys: %{authorized_keys: auth_keys}}
      } ->
        assert Map.has_key?(auth_keys, pub)
    end
  end
end
