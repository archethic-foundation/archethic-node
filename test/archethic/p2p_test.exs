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
          availability_history: <<1::1>>,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          first_public_key: pub2,
          last_public_key: pub2,
          available?: true,
          availability_history: <<1::1>>,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3004,
          first_public_key: pub3,
          last_public_key: pub3,
          available?: true,
          availability_history: <<1::1>>,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3005,
          first_public_key: pub4,
          last_public_key: pub4,
          available?: true,
          availability_history: <<1::1>>,
          network_patch: "AAA",
          geo_patch: "AAA"
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3006,
          first_public_key: pub5,
          last_public_key: pub5,
          available?: true,
          availability_history: <<1::1>>,
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
  end
end
