defmodule Archethic.SelfRepair.NetworkViewTest do
  # can't have async tests with the persistent_term
  use ArchethicCase, async: false

  import ArchethicCase

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.SelfRepair.NetworkView
  alias Archethic.TransactionChain.Transaction

  doctest NetworkView

  @persistent_keys Archethic.SharedSecrets.genesis_address_keys()

  describe "when node is down" do
    setup do
      :persistent_term.put(:archethic_up, :down)
      :persistent_term.put(@persistent_keys.origin, [])
      :persistent_term.put(@persistent_keys.nss, nil)

      start_supervised!(NetworkView)
      :ok
    end

    test "get_chains_hash should return an error if called before node is up" do
      :error = NetworkView.get_chains_hash()
    end

    test "load_transaction should return ok even if called before node is up" do
      :ok = NetworkView.load_transaction(%Transaction{type: :origin, address: random_address()})
    end

    test "init is triggered when node bootstrap is done" do
      # mock
      :persistent_term.put(@persistent_keys.origin, [
        random_address(),
        random_address(),
        random_address()
      ])

      :persistent_term.put(@persistent_keys.nss, random_address())
      Archethic.OracleChain.MemTable.put_addr(random_address(), DateTime.utc_now())

      # trigger the node_up event
      PubSub.notify_node_status(:node_up)

      assert hash = NetworkView.get_chains_hash()
      assert is_binary(hash)

      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :node_shared_secrets,
          address: random_address()
        })

      assert hash2 = NetworkView.get_chains_hash()
      assert is_binary(hash2)

      assert hash != hash2
    end

    test "get_p2p_hash should change return value on every node modification" do
      hash = NetworkView.get_p2p_hash()
      assert is_binary(hash)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "pubkey0",
        last_public_key: "pubkeylast",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      hash2 = NetworkView.get_p2p_hash()
      assert is_binary(hash2)

      assert hash != hash2
    end
  end

  # ---------------
  describe "when node is already up" do
    setup do
      :persistent_term.put(:archethic_up, :up)

      :persistent_term.put(@persistent_keys.origin, [
        random_address(),
        random_address(),
        random_address()
      ])

      :persistent_term.put(@persistent_keys.nss, random_address())
      Archethic.OracleChain.MemTable.put_addr(random_address(), DateTime.utc_now())

      start_supervised!(NetworkView)
      :ok
    end

    test "get_chains_hash should work" do
      assert hash = NetworkView.get_chains_hash()
      assert is_binary(hash)
    end

    test "load_transaction change the return value of get_chains_hash" do
      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :node_shared_secrets,
          address: random_address()
        })

      assert hash = NetworkView.get_chains_hash()
      assert is_binary(hash)

      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :node_shared_secrets,
          address: random_address()
        })

      assert hash2 = NetworkView.get_chains_hash()
      assert is_binary(hash2)

      assert hash != hash2

      :ok = NetworkView.load_transaction(%Transaction{type: :origin, address: random_address()})

      assert hash3 = NetworkView.get_chains_hash()
      assert is_binary(hash3)

      assert hash3 != hash2 && hash3 != hash

      :ok = NetworkView.load_transaction(%Transaction{type: :oracle, address: random_address()})

      assert hash4 = NetworkView.get_chains_hash()
      assert is_binary(hash4)

      assert hash4 != hash3 && hash4 != hash2 && hash4 != hash
    end
  end
end
