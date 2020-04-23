defmodule UnirisCore.Crypto.TransactionLoaderTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.Crypto
  alias UnirisCore.Crypto.TransactionLoader
  alias UnirisCore.Crypto.SoftwareKeystore

  import Mox

  setup do
    MockStorage
    |> stub(:node_transactions, fn -> [] end)
    |> stub(:get_last_node_shared_secrets_transaction, fn -> {:error, :transaction_not_exists} end)

    pid = start_supervised!(TransactionLoader)

    {:ok, %{pid: pid}}
  end

  test "when get a {:new_transaction, %Transaction{type: node} should increment crypto key if the node public key match the previous public key of the transaction",
       %{pid: pid} do
    previous_index_of_keys = Crypto.number_of_node_keys()

    MockStorage
    |> stub(:get_transaction, fn _ -> {:error, :transaction_not_exists} end)

    tx = Transaction.new(:node, %TransactionData{content: "ip: 127.0.0.1\nport: 3000"})
    send(pid, {:new_transaction, tx})
    Process.sleep(100)

    assert Crypto.number_of_node_keys() > previous_index_of_keys
  end

  test "when get {:new_transaction, %Transaction{type: :node_shared_secrets} should set node as authorized if presents in the shared secrets and decrypt the seeds",
       %{pid: pid} do
    aes_key = :crypto.strong_rand_bytes(32)
    seed = :crypto.strong_rand_bytes(32)

    Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(
      Crypto.aes_encrypt(seed, aes_key),
      Crypto.ec_encrypt(aes_key, Crypto.node_public_key())
    )

    authorized_keys =
      %{}
      |> Map.put(Crypto.node_public_key(), Crypto.ec_encrypt(aes_key, Crypto.node_public_key()))

    tx =
      Transaction.new(:node_shared_secrets, %TransactionData{
        keys: %{
          daily_nonce_seed: Crypto.aes_encrypt(seed, aes_key),
          transaction_seed: Crypto.aes_encrypt(seed, aes_key),
          authorized_keys: authorized_keys
        }
      })

    send(pid, {:new_transaction, tx})
    Process.sleep(100)

    assert %{daily_nonce_keys: _, node_secrets_transaction_seed: _} =
             :sys.get_state(SoftwareKeystore)
  end
end
