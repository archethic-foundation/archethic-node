defmodule Archethic.MiningTest do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.Mining
  alias Archethic.P2P
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.RequestChainLock
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionFactory

  use ArchethicCase
  import Mox

  setup do
    Enum.each(1..10, fn i ->
      P2P.add_and_connect_node(%Node{
        ip: {122, 12, 0, i},
        port: 300 + i,
        first_public_key: "node#{i}",
        last_public_key: "node#{i}",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })
    end)
  end

  describe "request_chain_lock" do
    setup do
      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :data,
          content: "something random"
        )

      hash =
        tx
        |> Transaction.to_pending()
        |> Transaction.serialize()
        |> Crypto.hash()

      %{tx: tx, hash: hash}
    end

    test "should request chain lock to all storage nodes", %{
      tx: tx = %Transaction{address: address},
      hash: hash
    } do
      message = %RequestChainLock{address: address, hash: hash}

      address
      |> Election.storage_nodes(P2P.authorized_and_available_nodes())
      |> Enum.each(fn node ->
        MockClient
        |> expect(:send_message, fn ^node, ^message, _ -> {:ok, %Ok{}} end)
      end)

      assert :ok == Mining.request_chain_lock(tx)
    end

    test "should return ok if at least 75% of storage nodes returned Ok", %{
      tx: tx = %Transaction{address: address},
      hash: hash
    } do
      message = %RequestChainLock{address: address, hash: hash}
      storage_nodes = Election.storage_nodes(address, P2P.authorized_and_available_nodes())
      nb_ok_nodes = ceil(length(storage_nodes) * 0.75)

      {ok_nodes, error_nodes} = Enum.split(storage_nodes, nb_ok_nodes)

      Enum.each(ok_nodes, fn node ->
        MockClient
        |> expect(:send_message, fn ^node, ^message, _ -> {:ok, %Ok{}} end)
      end)

      Enum.each(error_nodes, fn node ->
        MockClient
        |> expect(:send_message, fn ^node, ^message, _ ->
          {:ok, %Error{reason: :already_locked}}
        end)
      end)

      assert :ok == Mining.request_chain_lock(tx)
    end

    test "should return error if less than 75% of storage nodes returned Ok", %{
      tx: tx = %Transaction{address: address},
      hash: hash
    } do
      message = %RequestChainLock{address: address, hash: hash}
      storage_nodes = Election.storage_nodes(address, P2P.authorized_and_available_nodes())
      nb_ok_nodes = floor(length(storage_nodes) * 0.75)

      {ok_nodes, error_nodes} = Enum.split(storage_nodes, nb_ok_nodes)

      genesis_address = Crypto.derive_address(tx.previous_public_key)

      MockDB
      |> stub(:find_genesis_address, fn _ -> {:ok, genesis_address} end)

      Enum.each(ok_nodes, fn node ->
        MockClient
        |> expect(:send_message, fn ^node, ^message, _ -> {:ok, %Ok{}} end)
      end)

      Enum.each(error_nodes, fn node ->
        MockClient
        |> expect(:send_message, fn ^node, ^message, _ ->
          {:ok, %Error{reason: :already_locked}}
        end)
      end)

      assert {:error, :already_locked} == Mining.request_chain_lock(tx)
    end
  end
end
