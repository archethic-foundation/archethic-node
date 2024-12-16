defmodule Archethic.P2PTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction

  doctest Archethic.P2P

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "get_node_info/0 should return retrieve local node information" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key()
    })

    Process.sleep(100)

    assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info()
  end

  describe "quorum_read/3" do
    test "should return the first result when the same results are returned" do
      nodes = add_and_connect_nodes(5)

      MockClient
      |> expect(
        :send_message,
        3,
        fn _node, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}
        end
      )

      assert {:ok, %Transaction{}} = P2P.quorum_read(nodes, %GetTransaction{address: ""})
    end

    test "should run resolver conflicts when the results are different" do
      nodes = add_and_connect_nodes(5)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3004}, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}

        %Node{port: 3003}, %GetTransaction{}, _timeout ->
          {:ok, %NotFound{}}

        %Node{port: 3002}, %GetTransaction{}, _timeout ->
          {:ok, %NotFound{}}

        _, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}
      end)

      assert {:ok, %Transaction{}} =
               P2P.quorum_read(nodes, %GetTransaction{address: ""},
                 conflict_resolver: fn results ->
                   case Enum.find(results, &match?(%Transaction{}, &1)) do
                     nil ->
                       %NotFound{}

                     tx ->
                       tx
                   end
                 end
               )
    end

    test "should try all nodes and return error when no response match acceptance resolver" do
      nodes = add_and_connect_nodes(5)

      MockClient
      |> expect(
        :send_message,
        4,
        fn _node, _message, _timeout ->
          {:ok, %Transaction{}}
        end
      )
      |> expect(
        :send_message,
        1,
        fn _node, _message, _timeout ->
          :timer.sleep(200)
          {:ok, %NotFound{}}
        end
      )

      assert {:error, :acceptance_failed} =
               P2P.quorum_read(
                 nodes,
                 %GetTransaction{address: ""},
                 acceptance_resolver: fn _ -> false end
               )
    end

    test "should accept a single result for the entire set" do
      nodes = [node | _] = add_and_connect_nodes(5)

      MockClient
      |> stub(:send_message, fn
        ^node, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}

        _, %GetTransaction{}, _timeout ->
          {:error, :timeout}
      end)

      assert {:ok, %Transaction{}} =
               P2P.quorum_read(
                 nodes,
                 %GetTransaction{address: ""}
               )
    end

    test "should not accept a single result if not gone through the entire set" do
      nodes = [node, _, _, _, node5] = add_and_connect_nodes(5)

      me = self()

      MockClient
      |> stub(:send_message, fn
        ^node, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}

        ^node5, %GetTransaction{}, _timeout ->
          send(me, :node5_requested)

          {:ok, %NotFound{}}

        _, %GetTransaction{}, _timeout ->
          {:error, :timeout}
      end)

      assert {:ok, %Transaction{}} =
               P2P.quorum_read(
                 nodes,
                 %GetTransaction{address: ""}
               )

      assert_receive :node5_requested, 100
    end

    test "repair function should receive a nil accepted_result when no accepted response" do
      nodes = add_and_connect_nodes(5)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}
      end)

      me = self()

      assert {:error, :acceptance_failed} =
               P2P.quorum_read(
                 nodes,
                 %GetTransaction{address: ""},
                 acceptance_resolver: fn _ -> false end,
                 repair_fun: fn accepted_result, results_by_node ->
                   assert is_nil(accepted_result)
                   assert match?([{_, _} | _], results_by_node)
                   send(me, {:repairing, length(results_by_node)})
                   :ok
                 end
               )

      expected_size = length(nodes)
      assert_receive({:repairing, ^expected_size}, 100)
    end

    test "repair function should receive the accepted_result" do
      nodes = add_and_connect_nodes(5)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}
      end)

      me = self()

      assert {:ok, %Transaction{}} =
               P2P.quorum_read(
                 nodes,
                 %GetTransaction{address: ""},
                 repair_fun: fn accepted_result, results_by_node ->
                   assert %Transaction{} = accepted_result
                   assert match?([{_, _} | _], results_by_node)
                   send(me, {:repairing, length(results_by_node)})
                   :ok
                 end
               )

      # 3 is consistency_level
      assert_receive({:repairing, 3}, 100)
    end

    test "should call the repair function asynchronously" do
      nodes = add_and_connect_nodes(5)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _timeout ->
          {:ok, %Transaction{}}
      end)

      me = self()

      assert {:error, :acceptance_failed} =
               P2P.quorum_read(
                 nodes,
                 %GetTransaction{address: ""},
                 acceptance_resolver: fn _ -> false end,
                 repair_fun: fn _ ->
                   Process.sleep(10_000)
                   send(me, :repairing_done)
                   :ok
                 end
               )

      refute_received(:repairing_done)
    end
  end

  describe "authorized_and_available_nodes/1" do
    test "should not return authorized node before authorization_date" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: ~U[2022-09-11 01:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 00:00:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        authorized?: true,
        authorization_date: ~U[2022-09-11 02:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 00:00:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        authorized?: true,
        authorization_date: ~U[2022-09-11 03:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 00:00:00Z]
      })

      assert ["key1", "key2"] =
               P2P.authorized_and_available_nodes(~U[2022-09-11 02:00:00Z])
               |> Enum.map(& &1.first_public_key)
    end

    test "should not return available node before availability update" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: ~U[2022-09-11 00:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 01:10:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        authorized?: true,
        authorization_date: ~U[2022-09-11 00:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 01:00:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        authorized?: true,
        authorization_date: ~U[2022-09-11 00:00:00Z],
        available?: false,
        availability_update: ~U[2022-09-11 01:10:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key4",
        last_public_key: "key4",
        authorized?: true,
        authorization_date: ~U[2022-09-11 00:00:00Z],
        available?: false,
        availability_update: ~U[2022-09-11 01:00:00Z]
      })

      assert ["key2", "key3"] =
               P2P.authorized_and_available_nodes(~U[2022-09-11 01:05:00Z])
               |> Enum.map(& &1.first_public_key)
    end

    test "should return the first enrolled node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: ~U[2022-09-11 01:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 01:10:00Z],
        enrollment_date: ~U[2022-09-11 00:30:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        authorized?: true,
        authorization_date: ~U[2022-09-11 02:00:00Z],
        available?: true,
        availability_update: ~U[2022-09-11 02:10:00Z],
        enrollment_date: ~U[2022-09-11 01:30:00Z]
      })

      assert [%Node{first_public_key: "key1"}] =
               P2P.authorized_and_available_nodes(~U[2022-09-11 00:45:00Z])

      assert [%Node{first_public_key: "key1"}] =
               P2P.authorized_and_available_nodes(~U[2022-09-11 01:05:00Z])
    end
  end
end
