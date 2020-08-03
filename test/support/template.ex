defmodule UnirisCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Uniris.Crypto
  alias Uniris.Crypto.ECDSA

  alias Uniris.P2P.NodeSupervisor

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    File.rm_rf(Application.app_dir(:uniris, "priv/last_sync"))
    File.rm_rf(Application.app_dir(:uniris, "priv/storage"))

    MockStorage
    |> stub(:list_transactions, fn -> [] end)
    |> stub(:write_transaction, fn _ -> :ok end)
    |> stub(:write_transaction_chain, fn _ -> :ok end)
    |> stub(:get_transaction, fn _ -> {:error, :transaction_not_exists} end)
    |> stub(:get_transaction_chain, fn _ -> [] end)
    |> stub(:list_transaction_chains_info, fn -> [] end)

    MockCrypto
    |> stub(:sign_with_node_key, fn data ->
      {_, <<_::8, pv::binary>>} = Crypto.derivate_keypair("seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_key, fn data, index ->
      {_, <<_::8, pv::binary>>} = Crypto.derivate_keypair("seed", index, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_shared_secrets_key, fn data ->
      {_, <<_::8, pv::binary>>} = Crypto.derivate_keypair("seed", 0, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:sign_with_node_shared_secrets_key, fn data, index ->
      {_, <<_::8, pv::binary>>} = Crypto.derivate_keypair("seed", index, :secp256r1)
      ECDSA.sign(:secp256r1, pv, data)
    end)
    |> stub(:hash_with_daily_nonce, fn _ -> "hash" end)
    |> stub(:hash_with_storage_nonce, fn _ -> "hash" end)
    |> stub(:node_public_key, fn ->
      {pub, _} = Crypto.derivate_keypair("seed", 0, :secp256r1)
      pub
    end)
    |> stub(:node_public_key, fn index ->
      {pub, _} = Crypto.derivate_keypair("seed", index, :secp256r1)
      pub
    end)
    |> stub(:node_shared_secrets_public_key, fn index ->
      {pub, _} = Crypto.derivate_keypair("seed", index, :secp256r1)
      pub
    end)
    |> stub(:increment_number_of_generate_node_keys, fn -> :ok end)
    |> stub(:increment_number_of_generate_node_shared_secrets_keys, fn -> :ok end)
    |> stub(:decrypt_with_node_key!, fn _ -> :crypto.strong_rand_bytes(32) end)
    |> stub(:decrypt_with_node_key!, fn _, _ -> :crypto.strong_rand_bytes(32) end)
    |> stub(:derivate_beacon_chain_address, fn _, _ -> :crypto.strong_rand_bytes(32) end)
    |> stub(:number_of_node_keys, fn -> 0 end)
    |> stub(:number_of_node_shared_secrets_keys, fn -> 0 end)
    |> stub(:encrypt_node_shared_secrets_transaction_seed, fn _ ->
      :crypto.strong_rand_bytes(32)
    end)
    |> stub(:decrypt_and_set_node_shared_secrets_transaction_seed, fn _, _ -> :ok end)
    |> stub(:decrypt_and_set_daily_nonce_seed, fn _, _ -> :ok end)
    |> stub(:decrypt_and_set_storage_nonce, fn _ -> :ok end)
    |> stub(:decrypt_and_set_node_shared_secrets_network_pool_seed, fn _, _ -> :ok end)
    |> stub(:encrypt_storage_nonce, fn _ -> :crypto.strong_rand_bytes(32) end)

    start_supervised!(Uniris.Storage.Cache)

    on_exit(fn ->
      DynamicSupervisor.which_children(NodeSupervisor)
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(NodeSupervisor, pid)
      end)
    end)
  end
end
