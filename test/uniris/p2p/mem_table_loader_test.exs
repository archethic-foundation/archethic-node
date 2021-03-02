defmodule Uniris.P2P.MemTableLoaderTest do
  use UnirisCase

  alias Uniris.P2P.MemTable
  alias Uniris.P2P.MemTableLoader
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  describe "load_transaction/1" do
    test "should extract from transaction the node endpoint and the node to the table" do
      tx = create_node_transaction()
      assert :ok = MemTableLoader.load_transaction(tx)

      assert {:ok,
              %Node{
                ip: {127, 0, 0, 1},
                port: 3003,
                enrollment_date: ~U[2020-10-22 23:57:27.634295Z]
              }} = MemTable.get_node("Node1")
    end

    test "should add authorized nodes from node shared secrets transaction" do
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node1",
        last_public_key: "Node1"
      }
      |> MemTable.add_node()

      tx = create_node_shared_secrets_transaction()

      assert :ok = MemTableLoader.load_transaction(tx)
      assert ["Node1"] == MemTable.list_authorized_public_keys()
    end
  end

  describe "start_link/1" do
    test "should fetch the all the node transactions add integrate them" do
      node_tx = create_node_transaction()
      :ok = ChainLookup.add_transaction_by_type(node_tx.address, :node, node_tx.timestamp)

      MockDB
      |> stub(:get_transaction, fn address, _ ->
        if node_tx.address == address do
          {:ok, node_tx}
        else
          raise "Transaction not exists #{address}}"
        end
      end)

      assert {:ok, _} = MemTableLoader.start_link()
      assert ["Node1"] == MemTable.list_node_first_public_keys()
      assert [%Node{ip: {127, 0, 0, 1}, port: 3003}] = MemTable.list_nodes()
    end

    test "should fetch the last node shared secret transaction and integrate it" do
      MemTable.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node1",
        last_public_key: "Node1"
      })

      MemTable.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node4",
        last_public_key: "Node4"
      })

      shared_secret_tx1 = %Transaction{
        address: "@NodeSharedSecrets1",
        type: :node_shared_secrets,
        data: %TransactionData{
          keys: %Keys{
            authorized_keys: %{
              "Node1" => :crypto.strong_rand_bytes(32)
            }
          }
        },
        timestamp: DateTime.utc_now()
      }

      shared_secret_tx2 = %Transaction{
        address: "@NodeSharedSecrets2",
        type: :node_shared_secrets,
        data: %TransactionData{
          keys: %Keys{
            authorized_keys: %{
              "Node4" => :crypto.strong_rand_bytes(32)
            }
          }
        },
        timestamp: DateTime.utc_now() |> DateTime.add(10)
      }

      :ok =
        ChainLookup.add_transaction_by_type(
          shared_secret_tx1.address,
          :node_shared_secrets,
          shared_secret_tx1.timestamp
        )

      :ok =
        ChainLookup.add_transaction_by_type(
          shared_secret_tx2.address,
          :node_shared_secrets,
          shared_secret_tx2.timestamp
        )

      MockDB
      |> stub(:get_transaction, fn address, _ ->
        case address do
          "@NodeSharedSecrets1" ->
            {:ok, shared_secret_tx1}

          "@NodeSharedSecrets2" ->
            {:ok, shared_secret_tx2}
        end
      end)

      assert {:ok, _} = MemTableLoader.start_link()
      assert ["Node4"] == MemTable.list_authorized_public_keys()
    end
  end

  defp create_node_transaction do
    %Transaction{
      address: "@Node2",
      type: :node,
      data: %TransactionData{
        content: """
        ip: 127.0.0.1
        port: 3003
        transport: tcp
        """
      },
      previous_public_key: "Node1",
      timestamp: ~U[2020-10-22 23:57:27.634295Z]
    }
  end

  defp create_node_shared_secrets_transaction do
    %Transaction{
      address: "@NodeSharedSecrets1",
      type: :node_shared_secrets,
      data: %TransactionData{
        keys: %Keys{
          authorized_keys: %{
            "Node1" => :crypto.strong_rand_bytes(32)
          }
        }
      },
      timestamp: ~U[2020-10-22 23:57:27.634295Z]
    }
  end
end
