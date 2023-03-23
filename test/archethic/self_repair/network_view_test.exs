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

    test "get_xxx_hash should return an error if called before node is up" do
      assert :error = NetworkView.get_chains_hash()
      assert :error = NetworkView.get_p2p_hash()
    end

    test "load_transaction should return ok even if called before node is up" do
      software_public_key = <<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>

      assert :ok =
               NetworkView.load_transaction(%Transaction{
                 type: :origin,
                 address: random_address(),
                 previous_public_key: software_public_key
               })
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

      assert chains_hash = NetworkView.get_chains_hash()
      assert is_binary(chains_hash)

      assert p2p_hash = NetworkView.get_p2p_hash()
      assert is_binary(p2p_hash)
    end
  end

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

    test "load_transaction change the return value of get_p2p_hash" do
      software_public_key = <<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>
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

      NetworkView.load_transaction(%Transaction{
        type: :node,
        address: random_address(),
        previous_public_key: software_public_key
      })

      hash2 = NetworkView.get_p2p_hash()
      assert is_binary(hash2)

      assert hash != hash2
    end

    test "load_transaction change the return value of get_chains_hash" do
      software_public_key = <<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>

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
          address: random_address(),
          previous_public_key: software_public_key
        })

      assert hash2 = NetworkView.get_chains_hash()
      assert is_binary(hash2)

      assert hash != hash2

      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :origin,
          address: random_address(),
          previous_public_key: software_public_key
        })

      assert hash3 = NetworkView.get_chains_hash()
      assert is_binary(hash3)

      refute hash3 in [hash, hash2]

      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :oracle,
          address: random_address(),
          previous_public_key: software_public_key
        })

      assert hash4 = NetworkView.get_chains_hash()
      assert is_binary(hash4)

      refute hash4 in [hash, hash2, hash3]
    end

    test "load_transaction of type origin will change the correct state" do
      tpm_public_key = <<0::8, 2::8, :crypto.strong_rand_bytes(32)::binary>>
      software_public_key = <<0::8, 1::8, :crypto.strong_rand_bytes(32)::binary>>

      state = :sys.get_state(NetworkView)

      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :origin,
          address: random_address(),
          previous_public_key: tpm_public_key
        })

      state2 = :sys.get_state(NetworkView)

      assert state.origin.biometric == state2.origin.biometric
      assert state.origin.software == state2.origin.software
      refute state.origin.hardware == state2.origin.hardware

      :ok =
        NetworkView.load_transaction(%Transaction{
          type: :origin,
          address: random_address(),
          previous_public_key: software_public_key
        })

      state3 = :sys.get_state(NetworkView)

      assert state3.origin.biometric == state2.origin.biometric
      refute state3.origin.software == state2.origin.software
      assert state3.origin.hardware == state2.origin.hardware
    end
  end
end
