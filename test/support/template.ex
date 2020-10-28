defmodule UnirisCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.Crypto
  alias Uniris.Crypto.ECDSA

  alias Uniris.Election.Constraints

  alias Uniris.Governance.Pools.MemTable, as: PoolsMemTable

  alias Uniris.P2P.MemTable, as: P2PMemTable

  alias Uniris.SharedSecrets.MemTables.OriginKeyLookup

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.MemTables.KOLedger
  alias Uniris.TransactionChain.MemTables.PendingLedger

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    :persistent_term.put(:storage_nonce, "nonce")

    File.rm_rf(Application.app_dir(:uniris, "priv/p2p/last_sync_test"))

    MockDB
    |> stub(:list_transactions, fn _ -> [] end)
    |> stub(:write_transaction, fn _ -> :ok end)
    |> stub(:write_transaction_chain, fn _ -> :ok end)
    |> stub(:get_transaction, fn _, _ -> {:error, :transaction_not_exists} end)
    |> stub(:get_transaction_chain, fn _, _ -> [] end)

    {:ok, counter_node_keys_pid} = Agent.start_link(fn -> 0 end)
    {:ok, counter_node_shared_keys_pid} = Agent.start_link(fn -> 0 end)

    MockCrypto
    |> stub(:child_spec, fn _ -> {:ok, self()} end)
    |> stub(:sign_with_node_key, fn data ->
      {_, <<_::8, pv::binary>>} = Crypto.derive_keypair("seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_key, fn data, index ->
      {_, <<_::8, pv::binary>>} = Crypto.derive_keypair("seed", index, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_shared_secrets_key, fn data ->
      {_, <<_::8, pv::binary>>} = Crypto.derive_keypair("shared_secret_seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_shared_secrets_key, fn data, index ->
      {_, <<_::8, pv::binary>>} = Crypto.derive_keypair("shared_secret_seed", index, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:hash_with_daily_nonce, fn _ -> "hash" end)
    |> stub(:node_public_key, fn ->
      {pub, _} = Crypto.derive_keypair("seed", 0, :secp256r1)
      pub
    end)
    |> stub(:node_public_key, fn index ->
      {pub, _} = Crypto.derive_keypair("seed", index, :secp256r1)
      pub
    end)
    |> stub(:node_shared_secrets_public_key, fn index ->
      {pub, _} = Crypto.derive_keypair("shared_secret_seed", index, :secp256r1)
      pub
    end)
    |> stub(:increment_number_of_generate_node_keys, fn ->
      Agent.update(counter_node_keys_pid, &(&1 + 1))
    end)
    |> stub(:increment_number_of_generate_node_shared_secrets_keys, fn ->
      Agent.update(counter_node_shared_keys_pid, &(&1 + 1))
    end)
    |> stub(:decrypt_with_node_key!, fn cipher ->
      {_, pv} = Crypto.derive_keypair("seed", 0, :secp256r1)
      Crypto.ec_decrypt!(cipher, pv)
    end)
    |> stub(:number_of_node_keys, fn -> Agent.get(counter_node_keys_pid, & &1) end)
    |> stub(:number_of_node_shared_secrets_keys, fn ->
      Agent.get(counter_node_shared_keys_pid, & &1)
    end)
    |> stub(:encrypt_node_shared_secrets_transaction_seed, fn secret_key ->
      Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), secret_key)
    end)
    |> stub(:decrypt_and_set_node_shared_secrets_transaction_seed, fn _, _ -> :ok end)
    |> stub(:decrypt_and_set_daily_nonce_seed, fn _, _ -> :ok end)
    |> stub(:decrypt_and_set_node_shared_secrets_network_pool_seed, fn _, _ -> :ok end)

    start_supervised!(ChainLookup)
    start_supervised!(UCOLedger)
    start_supervised!(KOLedger)
    start_supervised!(PendingLedger)
    start_supervised!(OriginKeyLookup)
    start_supervised!(P2PMemTable)
    start_supervised!(Constraints)
    start_supervised!(PoolsMemTable)

    :ok
  end
end
