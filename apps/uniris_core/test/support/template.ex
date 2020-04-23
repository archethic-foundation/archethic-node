defmodule UnirisCoreCase do
  use ExUnit.CaseTemplate

  alias UnirisCore.P2P.NodeSupervisor
  alias UnirisCore.Crypto

  import Mox

  def set_storage_nonce(_) do
    Crypto.decrypt_and_set_storage_nonce(
      Crypto.ec_encrypt(
        "storage_seed",
        Crypto.node_public_key()
      )
    )
  end

  def set_daily_nonce(_) do
    aes_key = :crypto.strong_rand_bytes(32)
    encrypted_aes_key = Crypto.ec_encrypt(aes_key, Crypto.node_public_key())

    Crypto.decrypt_and_set_daily_nonce_seed(
      Crypto.aes_encrypt("daily_seed", aes_key),
      encrypted_aes_key
    )
  end

  def set_shared_secrets_transaction_seed(_) do
    aes_key = :crypto.strong_rand_bytes(32)
    encrypted_transaction_seed = Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), aes_key)
    encrypted_aes_key = Crypto.ec_encrypt(aes_key, Crypto.node_public_key())

    Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(
      encrypted_transaction_seed,
      encrypted_aes_key
    )
  end

  setup :set_storage_nonce
  setup :set_daily_nonce
  setup :set_shared_secrets_transaction_seed
  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    MockNodeClient
    |> stub(:start_link, fn _ -> {:ok, self()} end)

    Application.put_env(:uniris_core, UnirisCore.Storage, backend: MockStorage)
    Mox.defmock(MockStorage, for: UnirisCore.Storage.BackendImpl)

    MockStorage
    |> stub(:write_transaction, fn _ -> :ok end)
    |> stub(:write_transaction_chain, fn _ -> :ok end)
    |> stub(:get_transaction, fn _ -> {:ok, %{}} end)
    |> stub(:node_transactions, fn -> [] end)

    on_exit(fn ->
      DynamicSupervisor.which_children(NodeSupervisor)
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(NodeSupervisor, pid)
      end)
    end)
  end
end
