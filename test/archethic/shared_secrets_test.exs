defmodule Archethic.SharedSecretsTest do
  use ExUnit.Case, async: true

  alias Archethic.{Crypto, SharedSecrets, SharedSecrets.MemTables.OriginKeyLookup, P2P}
  alias Archethic.{TransactionChain.Transaction, TransactionChain.MemTables.KOLedger}
  alias Archethic.{Election, TransactionChain.Transaction.ValidationStamp}

  alias P2P.Message.{GetLastTransactionAddress, LastTransactionAddress}

  doctest SharedSecrets

  import Mox

  describe "has_origin_public_key?/1" do
    setup do
      start_supervised!(OriginKeyLookup)
      :ok
    end

    test "should return false when origin public key does not exist in Origin memtable" do
      {pb_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      refute SharedSecrets.has_origin_public_key?(pb_key)
    end

    test "should return true when origin public key does not exist in Origin memtable" do
      {pb_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      OriginKeyLookup.add_public_key(:software, pb_key)
      assert SharedSecrets.has_origin_public_key?(pb_key)
    end
  end

  describe "verify_synchronization" do
    setup do
      MockCrypto.NodeKeystore
      |> stub(:first_public_key, fn ->
        {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
        pub
      end)
      |> stub(:last_public_key, fn ->
        {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
        pub
      end)

      MockCrypto.SharedSecretsKeystore
      |> stub(:get_storage_nonce, fn -> "nonce" end)

      MockClient
      |> stub(:new_connection, fn _, _, _, public_key ->
        P2P.MemTable.increase_node_availability(public_key)
        {:ok, make_ref()}
      end)

      start_supervised!({KOLedger, []})
      start_supervised!({P2P.MemTable, []})
      start_supervised!(Election.Constraints)

      allow(MockCrypto.NodeKeystore, self(), P2P.MemTable)

      P2P.add_and_connect_node(%P2P.Node{
        first_public_key: Crypto.derive_keypair("seed", 0, :secp256r1) |> elem(0),
        last_public_key: Crypto.derive_keypair("seed", 0, :secp256r1) |> elem(0),
        authorized?: true,
        available?: true,
        authorization_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        geo_patch: "AAA",
        network_patch: "AAA",
        enrollment_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        reward_address: "Crypto.derive_address(Crypto.last_node_public_key())"
      })

      Process.sleep(50)
      :ok
    end

    test "validate_scheduling_time()" do
      keys = SharedSecrets.genesis_address_keys()

      :persistent_term.put(keys.nss, nil)
      refute SharedSecrets.validate_scheduling_time()

      nss_genesis_address = "nss_genesis_address"
      nss_last_address = "nss_last_address"
      :persistent_term.put(Map.get(keys, :nss), "nss_genesis_address")

      MockDB
      |> expect(:get_last_chain_address, 1, fn ^nss_genesis_address ->
        {nss_last_address, DateTime.utc_now()}
      end)
      |> expect(:get_transaction, 1, fn ^nss_last_address,
                                        [validation_stamp: [:timestamp]],
                                        :chain ->
        {:ok,
         %Transaction{
           validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
         }}
      end)

      assert SharedSecrets.validate_scheduling_time()

      MockDB
      |> expect(:get_last_chain_address, 1, fn ^nss_genesis_address ->
        {nss_last_address, DateTime.utc_now()}
      end)
      |> expect(:get_transaction, 1, fn ^nss_last_address,
                                        [validation_stamp: [:timestamp]],
                                        :chain ->
        {:ok, :error}
      end)

      refute SharedSecrets.validate_scheduling_time()
    end

    test "validate_last_address()" do
      keys = SharedSecrets.genesis_address_keys()

      :persistent_term.put(keys.nss, nil)
      assert :error == SharedSecrets.validate_last_address()

      nss_genesis_address = "nss_genesis_address"
      nss_last_address = "nss_last_address"
      :persistent_term.put(Map.get(keys, :nss), "nss_genesis_address")

      MockClient
      |> stub(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: nss_last_address}}
      end)

      MockDB
      |> stub(:get_last_chain_address, fn ^nss_genesis_address ->
        {nss_last_address, DateTime.utc_now()}
      end)

      assert :ok == SharedSecrets.validate_last_address()
    end
  end
end
