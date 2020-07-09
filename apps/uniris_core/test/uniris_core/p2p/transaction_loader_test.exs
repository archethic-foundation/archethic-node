defmodule UnirisCore.P2P.TransactionLoaderTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Crypto

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys

  alias UnirisCore.Mining.Context

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.P2P.TransactionLoader

  alias UnirisCore.Storage.Cache

  import Mox

  test "start_link/1 should start the transaction loader and preload stored transactions" do
    {public_key, _} = Crypto.derivate_keypair("seed", 0)

    node_tx =
      Transaction.new(
        :node,
        %TransactionData{
          content: """
          ip: 127.0.0.1
          port: 3000
          """
        },
        "seed",
        0
      )

    stamp =
      ValidationStamp.new(
        node_tx,
        %Context{},
        "welcome_node_public_key",
        "coordinator_public_key",
        ["cross_validation_node_public_keys"]
      )

    Cache.store_transaction(%{node_tx | validation_stamp: stamp})

    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("secret", secret_key)

    shared_secret_tx =
      Transaction.new(:node_shared_secrets, %TransactionData{
        keys: Keys.new([public_key], secret_key, secret)
      })

    stamp =
      ValidationStamp.new(
        shared_secret_tx,
        %Context{},
        "welcome_node_public_key",
        "coordinator_public_key",
        ["cross_validation_node_public_keys"]
      )

    Cache.store_transaction(%{shared_secret_tx | validation_stamp: stamp})

    TransactionLoader.start_link(renewal_interval: 0)
    Process.sleep(100)
    assert [%Node{first_public_key: public_key, authorized?: true}] = P2P.list_nodes()
  end

  test "when get {:new_transaction, %Transaction{type: node} should add the node in the system" do
    {:ok, pid} = TransactionLoader.start_link(renewal_interval: 0)
    tx = Transaction.new(:node, %TransactionData{content: "ip: 127.0.0.1\nport: 3000"}, "seed", 0)

    send(pid, {:new_transaction, tx})
    Process.sleep(100)
    assert length(P2P.list_nodes()) == 1
  end

  test "when get {:new_transaction, %Transaction{type: node} should update the node if the previous transaction exists" do
    {:ok, pid} = TransactionLoader.start_link(renewal_interval: 0)
    {pub, _} = Crypto.derivate_keypair("seed", 0)

    tx = Transaction.new(:node, %TransactionData{content: "ip: 127.0.0.1\nport: 3000"}, "seed", 0)

    send(pid, {:new_transaction, tx})
    Process.sleep(100)

    assert {:ok, %Node{port: 3000}} = P2P.node_info(pub)

    MockStorage
    |> expect(:get_transaction, fn _ ->
      {:ok, tx}
    end)

    tx = Transaction.new(:node, %TransactionData{content: "ip: 127.0.0.1\nport: 5000"}, "seed", 1)

    send(pid, {:new_transaction, tx})
    Process.sleep(100)

    assert {:ok, %Node{port: 5000}} = P2P.node_info(pub)
  end

  test "when get {:new_transaction, %Transaction{type: :node_shared_secrets} authorize the nodes after the renewal interval time" do
    {:ok, pid} = TransactionLoader.start_link(renewal_interval: 0)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key()
    })

    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("secret", secret_key)

    tx =
      Transaction.new(:node_shared_secrets, %TransactionData{
        keys: Keys.new([Crypto.node_public_key()], secret_key, secret)
      })

    send(pid, {:new_transaction, tx})
    Process.sleep(200)

    assert {:ok, %Node{authorized?: true}} = P2P.node_info(Crypto.node_public_key())
  end
end
