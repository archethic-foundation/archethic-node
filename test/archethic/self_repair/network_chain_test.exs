defmodule Archethic.SelfRepair.NetworkChainTest do
  # Cannot be async because it depends on global RepairWorker
  use ArchethicCase, async: false

  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.NodeList
  alias Archethic.P2P.Message.ListNodes
  alias Archethic.P2P.Node
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.NetworkChain

  import Mox
  import Mock

  describe "synchronous_resync (non-node)" do
    setup do
      OracleChain.MemTable.put_addr(random_address(), DateTime.utc_now())

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })
    end

    test "should start a resync when remote /= local" do
      last_address = random_address()
      now = DateTime.utc_now()
      oracle_genesis_address = OracleChain.genesis_address()

      MockDB
      |> expect(:get_last_chain_address, 2, fn address ->
        {address, DateTime.add(now, -1, :minute)}
      end)

      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: last_address, timestamp: now}}
      end)

      with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
        :ok = NetworkChain.synchronous_resync(:oracle)
        assert_called(SelfRepair.replicate_transaction(last_address, oracle_genesis_address))
      end
    end

    test "should not start a resync when remote == local" do
      last_address = random_address()
      now = DateTime.utc_now()
      oracle_genesis_address = OracleChain.genesis_address()

      MockDB
      |> expect(:get_last_chain_address, 2, fn _ ->
        {last_address, now}
      end)

      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: last_address, timestamp: now}}
      end)

      with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
        :ok = NetworkChain.synchronous_resync(:oracle)
        assert_not_called(SelfRepair.replicate_transaction(last_address, oracle_genesis_address))
      end
    end
  end

  describe "synchronous_resync (node)" do
    test "should start a resync when remote /= local" do

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        last_address: Crypto.derive_address(Crypto.last_node_public_key()),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        enrollment_date: DateTime.utc_now() |> DateTime.add(-1),
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      }

      P2P.add_and_connect_node(node)

      last_public_key = random_public_key()
      last_address = Crypto.derive_address(last_public_key)
      genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()

      MockClient
      |> expect(:send_message, fn _, %ListNodes{}, _ ->
        {:ok,
         %NodeList{
           nodes: [%Node{node | last_public_key: last_public_key, last_address: last_address}]
         }}
      end)

      with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
        :ok = NetworkChain.synchronous_resync(:node)
        assert_called(SelfRepair.replicate_transaction(last_address, genesis_address))
      end
    end
  end
end
