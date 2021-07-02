defmodule ArchEthicCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias ArchEthic.Account.MemTables.NFTLedger
  alias ArchEthic.Account.MemTables.UCOLedger

  alias ArchEthic.Crypto
  alias ArchEthic.Crypto.ECDSA

  alias ArchEthic.Election.Constraints

  alias ArchEthic.Governance.Pools.MemTable, as: PoolsMemTable

  alias ArchEthic.OracleChain.MemTable, as: OracleMemTable

  alias ArchEthic.P2P.MemTable, as: P2PMemTable

  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup
  alias ArchEthic.SharedSecrets.MemTables.OriginKeyLookup

  alias ArchEthic.TransactionChain.MemTables.KOLedger
  alias ArchEthic.TransactionChain.MemTables.PendingLedger

  alias ArchEthic.Utils

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    :persistent_term.put(:storage_nonce, "nonce")

    Path.wildcard(Utils.mut_dir()) |> Enum.each(&File.rm_rf!/1)

    MockDB
    |> stub(:list_transactions, fn _ -> [] end)
    |> stub(:write_transaction, fn _ -> :ok end)
    |> stub(:write_transaction_chain, fn _ -> :ok end)
    |> stub(:get_transaction, fn _, _ -> {:error, :transaction_not_exists} end)
    |> stub(:get_transaction_chain, fn _, _ -> [] end)
    |> stub(:list_last_transaction_addresses, fn -> [] end)
    |> stub(:add_last_transaction_address, fn _, _, _ -> :ok end)
    |> stub(:get_last_chain_address, fn addr -> addr end)
    |> stub(:get_last_chain_address, fn addr, _ -> addr end)
    |> stub(:get_first_public_key, fn pub -> pub end)
    |> stub(:get_first_chain_address, fn addr -> addr end)
    |> stub(:chain_size, fn _ -> 0 end)
    |> stub(:list_transactions_by_type, fn _, _ -> [] end)
    |> stub(:count_transactions_by_type, fn _ -> 0 end)
    |> stub(:list_transactions, fn _ -> [] end)
    |> stub(:transaction_exists?, fn _ -> false end)

    {:ok, shared_secrets_counter} = Agent.start_link(fn -> 0 end)
    {:ok, network_pool_counter} = Agent.start_link(fn -> 0 end)

    MockCrypto
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
    |> stub(:diffie_hellman, fn pub ->
      {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      :crypto.compute_key(:ecdh, pub, pv, :secp256r1)
    end)
    |> stub(:next_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 1, :secp256r1)
      pub
    end)
    |> stub(:persist_next_keypair, fn -> :ok end)
    |> stub(:get_network_pool_key_index, fn -> Agent.get(network_pool_counter, & &1) end)
    |> stub(:get_node_shared_key_index, fn -> Agent.get(shared_secrets_counter, & &1) end)
    |> stub(:set_network_pool_key_index, fn index ->
      Agent.update(network_pool_counter, fn _ -> index end)
    end)
    |> stub(:set_node_shared_secrets_key_index, fn index ->
      Agent.update(shared_secrets_counter, fn _ -> index end)
    end)

    MockClient
    |> stub(:new_connection, fn _, _, _, _ -> {:ok, make_ref()} end)

    start_supervised!(NFTLedger)
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
