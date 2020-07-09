defmodule UnirisCore.Crypto.TransactionLoaderTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Crypto
  alias UnirisCore.Crypto.TransactionLoader

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys

  import Mox

  setup do
    pid = start_supervised!({TransactionLoader, renewal_interval: 100})

    {:ok, %{pid: pid}}
  end

  test "when get a {:new_transaction, %Transaction{type: node} should increment crypto key if the node public key match the previous public key of the transaction",
       %{pid: pid} do
    {:ok, agent_pid} = Agent.start_link(fn -> %{number_of_node_keys: 0} end)

    MockStorage
    |> stub(:get_transaction, fn _ -> {:error, :transaction_not_exists} end)

    MockCrypto
    |> expect(:increment_number_of_generate_node_keys, fn ->
      Agent.update(agent_pid, fn state -> Map.update!(state, :number_of_node_keys, &(&1 + 1)) end)
    end)

    tx = Transaction.new(:node, %TransactionData{content: "ip: 127.0.0.1\nport: 3000"})
    send(pid, {:new_transaction, tx})
    Process.sleep(100)

    assert Agent.get(agent_pid, & &1.number_of_node_keys) == 1
  end

  test "when get {:new_transaction, %Transaction{type: :node_shared_secrets} should decrypt and load the seeds",
       %{pid: pid} do
    {:ok, agent_pid} = Agent.start_link(fn -> %{} end)

    aes_key = :crypto.strong_rand_bytes(32)
    seed = :crypto.strong_rand_bytes(32)

    MockCrypto
    |> stub(:decrypt_and_set_node_shared_secrets_transaction_seed, fn encrypted_seed,
                                                                      encrypted_aes_key ->
      Agent.update(agent_pid, fn state ->
        {_, pv} = Crypto.derivate_keypair("seed", 0, :secp256r1)
        aes_key = Crypto.ec_decrypt!(encrypted_aes_key, pv)
        transaction_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)
        Map.put(state, :node_secrets_transaction_seed, transaction_seed)
      end)
    end)
    |> stub(:decrypt_and_set_daily_nonce_seed, fn encrypted_seed, encrypted_aes_key ->
      Agent.update(agent_pid, fn state ->
        {_, pv} = Crypto.derivate_keypair("seed", 0, :secp256r1)
        aes_key = Crypto.ec_decrypt!(encrypted_aes_key, pv)
        daily_nonce_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)
        keys = Crypto.generate_deterministic_keypair(daily_nonce_seed)
        Map.put(state, :daily_nonce_keys, keys)
      end)
    end)

    {pub, _} = Crypto.derivate_keypair("seed", 0, :secp256r1)

    encrypted_daily_nonce = Crypto.aes_encrypt(seed, aes_key)
    encrypted_transaction_seed = Crypto.aes_encrypt(seed, aes_key)

    secret = encrypted_daily_nonce <> encrypted_transaction_seed

    tx =
      Transaction.new(:node_shared_secrets, %TransactionData{
        keys:
          Keys.new(
            [pub],
            aes_key,
            secret
          )
      })

    send(pid, {:new_transaction, tx})
    Process.sleep(200)

    assert %{daily_nonce_keys: _, node_secrets_transaction_seed: seed} =
             Agent.get(agent_pid, & &1)
  end
end
