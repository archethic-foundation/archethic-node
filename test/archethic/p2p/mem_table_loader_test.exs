defmodule Archethic.P2P.MemTableLoaderTest do
  use ArchethicCase

  alias Archethic.P2P.MemTable
  alias Archethic.P2P.MemTableLoader
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  @node_1_public_key <<0, 0, :crypto.strong_rand_bytes(32)::binary>>
  @node_2_public_key <<0, 0, :crypto.strong_rand_bytes(32)::binary>>

  describe "load_transaction/1" do
    test "should extract from transaction the node endpoint and the node to the table" do
      tx = create_node_transaction()

      MockDB
      |> expect(:get_first_public_key, fn pub -> pub end)

      assert :ok = MemTableLoader.load_transaction(tx)

      assert {:ok,
              %Node{
                ip: {127, 0, 0, 1},
                port: 3003,
                enrollment_date: ~U[2020-10-22 23:57:27.634295Z]
              }} = MemTable.get_node(@node_1_public_key)
    end

    test "should add authorized nodes from node shared secrets transaction" do
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: @node_1_public_key,
        last_public_key: @node_1_public_key
      }
      |> MemTable.add_node()

      tx = create_node_shared_secrets_transaction()

      assert :ok = MemTableLoader.load_transaction(tx)
      assert [@node_1_public_key] == MemTable.list_authorized_public_keys()
    end
  end

  describe "start_link/1" do
    test "should fetch the all the node transactions add integrate them" do
      node_tx = create_node_transaction()

      MockDB
      |> stub(:list_transactions_by_type, fn :node, _ ->
        [node_tx]
      end)
      |> expect(:get_first_public_key, fn pub -> pub end)

      assert {:ok, _} = MemTableLoader.start_link()
      assert [@node_1_public_key] == MemTable.list_node_first_public_keys()
      assert [%Node{ip: {127, 0, 0, 1}, port: 3003}] = MemTable.list_nodes()
    end

    test "should fetch the last node shared secret transaction and integrate it" do
      MemTable.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: @node_1_public_key,
        last_public_key: @node_1_public_key
      })

      MemTable.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: @node_2_public_key,
        last_public_key: @node_2_public_key
      })

      shared_secret_tx1 = %Transaction{
        address: "@NodeSharedSecrets1",
        type: :node_shared_secrets,
        data: %TransactionData{
          ownerships: [
            %Ownership{
              authorized_keys: %{
                @node_1_public_key => :crypto.strong_rand_bytes(32)
              }
            }
          ]
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now()
        }
      }

      shared_secret_tx2 = %Transaction{
        address: "@NodeSharedSecrets2",
        type: :node_shared_secrets,
        data: %TransactionData{
          ownerships: [
            %Ownership{
              authorized_keys: %{
                @node_2_public_key => :crypto.strong_rand_bytes(32)
              }
            }
          ]
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now() |> DateTime.add(10)
        }
      }

      MockDB
      |> stub(:list_transactions_by_type, fn :node, _ -> [] end)
      |> stub(:list_addresses_by_type, fn :node_shared_secrets ->
        [
          shared_secret_tx1.address,
          shared_secret_tx2.address
        ]
      end)
      |> stub(:get_transaction, fn address, _ ->
        cond do
          address == shared_secret_tx1.address ->
            {:ok, shared_secret_tx1}

          address == shared_secret_tx2.address ->
            {:ok, shared_secret_tx2}

          true ->
            {:error, :transaction_not_exists}
        end
      end)

      assert {:ok, _} = MemTableLoader.start_link()
      assert [@node_2_public_key] == MemTable.list_authorized_public_keys()
    end
  end

  defp create_node_transaction do
    %Transaction{
      address: "@Node2",
      type: :node,
      data: %TransactionData{
        content:
          <<127, 0, 0, 1, 3003::16, 4000::16, 1, 0, 0, 163, 237, 233, 93, 14, 241, 241, 8, 144,
            218, 105, 16, 138, 243, 223, 17, 182, 87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35,
            209, 142, 24, 164, <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>, 64::16,
            :crypto.strong_rand_bytes(64)::binary>>
      },
      previous_public_key: @node_1_public_key,
      validation_stamp: %ValidationStamp{
        timestamp: ~U[2020-10-22 23:57:27.634295Z]
      }
    }
  end

  defp create_node_shared_secrets_transaction do
    %Transaction{
      address: "@NodeSharedSecrets1",
      type: :node_shared_secrets,
      data: %TransactionData{
        ownerships: [
          %Ownership{
            authorized_keys: %{
              @node_1_public_key => :crypto.strong_rand_bytes(32)
            }
          }
        ]
      },
      validation_stamp: %ValidationStamp{
        timestamp: ~U[2020-10-22 23:57:27.634295Z]
      }
    }
  end
end
