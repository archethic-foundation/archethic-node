defmodule Archethic.P2PTest do
  use ArchethicCase

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

  describe "quorum_read/4" do
    setup do
      pub1 = Crypto.generate_deterministic_keypair("node1") |> elem(0)
      pub2 = Crypto.generate_deterministic_keypair("node2") |> elem(0)
      pub3 = Crypto.generate_deterministic_keypair("node3") |> elem(0)
      pub4 = Crypto.generate_deterministic_keypair("node4") |> elem(0)
      pub5 = Crypto.generate_deterministic_keypair("node5") |> elem(0)

      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          first_public_key: pub1,
          last_public_key: pub1,
          available?: true,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          first_public_key: pub2,
          last_public_key: pub2,
          available?: true,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3004,
          first_public_key: pub3,
          last_public_key: pub3,
          available?: true,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3005,
          first_public_key: pub4,
          last_public_key: pub4,
          available?: true,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3006,
          first_public_key: pub5,
          last_public_key: pub5,
          available?: true,
          network_patch: "AAA",
          geo_patch: "AAA"
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)
      {:ok, %{nodes: nodes}}
    end

    test "should return the first result when the same results are returned", %{nodes: nodes} do
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

    test "should run resolver conflicts when the results are different", %{nodes: nodes} do
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
               P2P.quorum_read(nodes, %GetTransaction{address: ""}, fn results ->
                 case Enum.find(results, &match?(%Transaction{}, &1)) do
                   nil ->
                     %NotFound{}

                   tx ->
                     tx
                 end
               end)
    end

    test "should try all nodes and return error when no response match acceptance resolver",
         %{
           nodes: nodes
         } do
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
                 fn results -> List.last(results) end,
                 0,
                 fn _ -> false end
               )
    end

    test "should call the repair function for every results", %{nodes: nodes} do
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
                 fn results -> List.first(results) end,
                 0,
                 fn _ -> false end,
                 3,
                 fn all_results ->
                   assert match?([{_, _} | _], all_results)
                   Process.send(me, {:repairing, length(all_results)}, [])
                   Process.sleep(10_000)
                   :ok
                 end
               )

      expected_size = length(nodes)
      assert_receive({:repairing, ^expected_size}, 100)
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
