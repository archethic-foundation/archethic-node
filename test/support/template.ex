defmodule ArchethicCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.Crypto
  alias Archethic.Crypto.ECDSA

  alias Archethic.Election.Constraints

  alias Archethic.Governance.Pools.MemTable, as: PoolsMemTable

  alias Archethic.OracleChain.MemTable, as: OracleMemTable

  alias Archethic.P2P.MemTable, as: P2PMemTable

  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup

  alias Archethic.TransactionChain.MemTables.KOLedger
  alias Archethic.TransactionChain.MemTables.PendingLedger

  alias Archethic.Utils

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    File.rm_rf!(Utils.mut_dir())

    MockDB
    |> stub(:list_transactions, fn _ -> [] end)
    |> stub(:write_transaction, fn _ -> :ok end)
    |> stub(:write_transaction_chain, fn _ -> :ok end)
    |> stub(:get_transaction, fn _, _ -> {:error, :transaction_not_exists} end)
    |> stub(:get_transaction_chain, fn _, _, _ -> {[], false, nil} end)
    |> stub(:list_last_transaction_addresses, fn -> [] end)
    |> stub(:add_last_transaction_address, fn _, _, _ -> :ok end)
    |> stub(:get_last_chain_address, fn addr -> addr end)
    |> stub(:get_last_chain_address, fn addr, _ -> addr end)
    |> stub(:get_first_public_key, fn pub -> pub end)
    |> stub(:get_first_chain_address, fn addr -> addr end)
    |> stub(:chain_size, fn _ -> 0 end)
    |> stub(:list_transactions_by_type, fn _, _ -> [] end)
    |> stub(:count_transactions_by_type, fn _ -> 0 end)
    |> stub(:list_addresses_by_type, fn _ -> [] end)
    |> stub(:list_transactions, fn _ -> [] end)
    |> stub(:transaction_exists?, fn _ -> false end)
    |> stub(:register_p2p_summary, fn _, _, _, _ -> :ok end)
    |> stub(:get_last_p2p_summaries, fn -> [] end)
    |> stub(:get_bootstrap_info, fn
      "storage_nonce" ->
        "nonce"

      "last_sync_time" ->
        nil

      "node_keys_index" ->
        nil

      "bootstrapping_seeds" ->
        "127.0.0.1:3002:0100044D91A0A1A7CF06A2902D3842F82D2791BCBF3EE6F6DC8DE0F90E53E9991C3CB33684B7B9E66F26E7C9F5302F73C69897BE5F301DE9A63521A08AC4EF34C18728:tcp"
    end)
    |> stub(:set_bootstrap_info, fn _, _ -> :ok end)

    {:ok, shared_secrets_counter} = Agent.start_link(fn -> 0 end)
    {:ok, network_pool_counter} = Agent.start_link(fn -> 0 end)

    MockCrypto
    |> stub(:last_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
      pub
    end)
    |> stub(:first_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
      pub
    end)
    |> stub(:previous_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
      pub
    end)
    |> stub(:next_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 1, :secp256r1)
      pub
    end)
    |> stub(:persist_next_keypair, fn -> :ok end)
    |> stub(:sign_with_first_key, fn data ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_last_key, fn data ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_previous_key, fn data ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:diffie_hellman_with_last_key, fn pub ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      :crypto.compute_key(:ecdh, pub, pv, :secp256r1)
    end)
    |> stub(:diffie_hellman_with_first_key, fn pub ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      :crypto.compute_key(:ecdh, pub, pv, :secp256r1)
    end)
    |> stub(:sign_with_node_shared_secrets_key, fn data ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("shared_secret_seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_shared_secrets_key, fn data, index ->
      {_, <<_::8, _::8, pv::binary>>} =
        Crypto.derive_keypair("shared_secret_seed", index, :secp256r1)

      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_network_pool_key, fn data ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("network_pool_seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_network_pool_key, fn data, index ->
      {_, <<_::8, _::8, pv::binary>>} =
        Crypto.derive_keypair("network_pool_seed", index, :secp256r1)

      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_daily_nonce_key, fn data, _ ->
      {_, pv} = Crypto.generate_deterministic_keypair("daily_nonce_seed")
      Crypto.sign(data, pv)
    end)
    |> stub(:sign_with_origin_key, fn data ->
      {_, pv} = Crypto.derive_keypair("seed", 0, :secp256r1)
      Crypto.sign(data, pv)
    end)
    |> stub(:origin_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
      pub
    end)
    |> stub(:node_shared_secrets_public_key, fn index ->
      {pub, _} = Crypto.derive_keypair("shared_secret_seed", index, :secp256r1)
      pub
    end)
    |> stub(:network_pool_public_key, fn index ->
      {pub, _} = Crypto.derive_keypair("network_pool_seed", index, :secp256r1)
      pub
    end)
    |> stub(:wrap_secrets, fn secret_key ->
      encrypted_transaction_seed = Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), secret_key)
      encrypted_network_pool_seed = Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), secret_key)

      {encrypted_transaction_seed, encrypted_network_pool_seed}
    end)
    |> stub(:unwrap_secrets, fn _, _, _ -> :ok end)
    |> stub(:get_network_pool_key_index, fn -> Agent.get(network_pool_counter, & &1) end)
    |> stub(:get_node_shared_key_index, fn -> Agent.get(shared_secrets_counter, & &1) end)
    |> stub(:set_network_pool_key_index, fn index ->
      Agent.update(network_pool_counter, fn _ -> index end)
    end)
    |> stub(:set_node_shared_secrets_key_index, fn index ->
      Agent.update(shared_secrets_counter, fn _ -> index end)
    end)
    |> stub(:get_storage_nonce, fn -> "nonce" end)
    |> stub(:set_storage_nonce, fn _ -> :ok end)

    MockClient
    |> stub(:new_connection, fn _, _, _, _ -> {:ok, make_ref()} end)

    start_supervised!(TokenLedger)
    start_supervised!(UCOLedger)
    start_supervised!(KOLedger)
    start_supervised!(PendingLedger)
    start_supervised!(OriginKeyLookup)
    start_supervised!(P2PMemTable)
    start_supervised!(Constraints)
    start_supervised!(PoolsMemTable)
    start_supervised!(NetworkLookup)
    start_supervised!(OracleMemTable)
    :ok
  end
end
