defmodule Uniris.Storage.Memory.NetworkLedgerTest do
  use ExUnit.Case

  alias Uniris.Crypto

  alias Uniris.P2P.Node

  alias Uniris.Storage.Memory.NetworkLedger

  alias Uniris.Transaction
  alias Uniris.TransactionData

  import Mox

  setup :set_mox_global

  setup do
    MockStorage
    |> stub(:list_transactions_by_type, fn _type, _fields ->
      []
    end)

    :ok
  end

  test "add_node_info/1 should add to the memory table the node" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA",
      authorized?: true
    })

    assert [
             %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               first_public_key: "Node0",
               last_public_key: "Node10",
               geo_patch: "AAA",
               authorized?: true
             }
           ] = NetworkLedger.list_nodes()
  end

  test "authorize_node/2 should flag the node (identified by  first public key) as authorized" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.authorize_node("Node0", ~U[2020-08-27 16:50:38.192760Z])

    assert [
             %Node{
               authorized?: true,
               authorization_date: ~U[2020-08-27 16:50:38.192760Z]
             }
           ] = NetworkLedger.list_nodes()

    assert [
             %Node{
               authorized?: true,
               authorization_date: ~U[2020-08-27 16:50:38.192760Z]
             }
           ] = NetworkLedger.list_authorized_nodes()
  end

  test "reset_authorized_nodes/0 should unauthorized the nodes" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    :ok = NetworkLedger.authorize_node("Node0", ~U[2020-08-27 16:50:38.192760Z])

    assert :ok = NetworkLedger.reset_authorized_nodes()

    assert [] = NetworkLedger.list_authorized_nodes()
  end

  test "update_node_average_availability/2 should update avg availability" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.update_node_average_availability("Node0", 0.85)

    assert [
             %Node{
               average_availability: 0.85
             }
           ] = NetworkLedger.list_nodes()
  end

  test "update_network_patch/2 should update node network patch" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.update_node_network_patch("Node0", "FAB")

    assert [
             %Node{
               network_patch: "FAB"
             }
           ] = NetworkLedger.list_nodes()
  end

  test "set_node_ready/2 should mark a node as ready" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.set_node_ready("Node0", ~U[2020-08-27 16:50:38.192760Z])

    assert [
             %Node{
               ready?: true,
               ready_date: ~U[2020-08-27 16:50:38.192760Z]
             }
           ] = NetworkLedger.list_nodes()

    assert [
             %Node{
               ready?: true,
               ready_date: ~U[2020-08-27 16:50:38.192760Z]
             }
           ] = NetworkLedger.list_ready_nodes()
  end

  test "set_node_enrollment_date/2 should define the date when the node joins the network" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.set_node_enrollment_date("Node0", ~U[2020-08-27 16:50:38.192760Z])

    assert [
             %Node{
               enrollment_date: ~U[2020-08-27 16:50:38.192760Z]
             }
           ] = NetworkLedger.list_nodes()
  end

  test "set_node_available/1 mark the node as available" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.set_node_available("Node0")

    assert [
             %Node{
               available?: true
             }
           ] = NetworkLedger.list_nodes()
  end

  test "set_node_unavailable/1 mark the node as unavailable" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.set_node_unavailable("Node0")

    assert [
             %Node{
               available?: false
             }
           ] = NetworkLedger.list_nodes()
  end

  test "increase_node_availability/1 should update the node availability history" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA",
      availability_history: <<0::1>>
    })

    assert :ok = NetworkLedger.increase_node_availability("Node0")

    assert [
             %Node{
               availability_history: <<1::1, 0::1>>
             }
           ] = NetworkLedger.list_nodes()
  end

  test "decrease_node_availability/1 should update the node availability history" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert :ok = NetworkLedger.increase_node_availability("Node0")

    assert [
             %Node{
               availability_history: <<1::1>>
             }
           ] = NetworkLedger.list_nodes()

    assert :ok = NetworkLedger.decrease_node_availability("Node0")

    assert [
             %Node{
               availability_history: <<0::1, 1::1>>
             }
           ] = NetworkLedger.list_nodes()
  end

  test "get_node_info/1 should return the node P2P details if the node exists" do
    NetworkLedger.start_link()

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "Node0",
      last_public_key: "Node10",
      geo_patch: "AAA"
    })

    assert {:ok, %Node{ip: {127, 0, 0, 1}, port: 3000}} = NetworkLedger.get_node_info("Node0")
  end

  test "get_node_first_public_key_from_previous_key/1 should retrieve the first node key by a the previous public key" do
    NetworkLedger.start_link()

    NetworkLedger.load_transaction(%Transaction{
      address: Crypto.hash("Node1"),
      type: :node,
      previous_public_key: "Node0",
      data: %TransactionData{
        content: """
        ip: 127.0.0.1
        port: 3000
        """
      }
    })

    assert "Node0" == NetworkLedger.get_node_first_public_key_from_previous_key("Node0")

    NetworkLedger.load_transaction(%Transaction{
      address: Crypto.hash("Node2"),
      type: :node,
      previous_public_key: "Node1",
      data: %TransactionData{
        content: """
        ip: 127.0.0.1
        port: 3000
        """
      }
    })

    assert "Node0" == NetworkLedger.get_node_first_public_key_from_previous_key("Node1")
  end

  test "count_node_changes/1 should return the number of times a nodes has been updated" do
    NetworkLedger.start_link()

    NetworkLedger.load_transaction(%Transaction{
      address: Crypto.hash("Node1"),
      type: :node,
      data: %TransactionData{
        content: """
        ip: 127.0.0.1
        port: 3000
        """
      },
      previous_public_key: "Node0"
    })

    NetworkLedger.load_transaction(%Transaction{
      address: Crypto.hash("Node2"),
      type: :node,
      data: %TransactionData{
        content: """
        ip: 127.0.0.1
        port: 3000
        """
      },
      previous_public_key: "Node1"
    })

    assert 2 == NetworkLedger.count_node_changes("Node0")
  end

  test "start_link/1 should create ets tables and load network transactions " do
    MockStorage
    |> stub(:list_transactions_by_type, fn type, _fields ->
      case type do
        :node ->
          [
            %Transaction{
              address: Crypto.hash("Node2"),
              type: :node,
              timestamp: DateTime.utc_now(),
              previous_public_key: "Node1",
              data: %TransactionData{
                content: """
                ip: 127.0.0.1
                port: 5000
                """
              }
            },
            %Transaction{
              address: Crypto.hash("Node1"),
              type: :node,
              timestamp: DateTime.utc_now() |> DateTime.add(-1),
              previous_public_key: "Node0",
              data: %TransactionData{
                content: """
                ip: 127.0.0.1
                port: 5000
                """
              }
            }
          ]

        :node_shared_secrets ->
          [
            %Transaction{
              address: Crypto.hash("NodeSharedSecrets1"),
              timestamp: DateTime.utc_now(),
              type: :node_shared_secrets
            }
          ]

        :origin_shared_secrets ->
          [
            %Transaction{
              address: Crypto.hash("OriginSharedSecrets1"),
              timestamp: DateTime.utc_now(),
              type: :origin_shared_secrets,
              data: %TransactionData{content: ""}
            }
          ]

        :code_proposal ->
          [
            %Transaction{
              address: Crypto.hash("CodeProposal1"),
              timestamp: DateTime.utc_now(),
              type: :code_proposal,
              data: %TransactionData{content: ""}
            }
          ]
      end
    end)

    NetworkLedger.start_link()
    assert [Crypto.hash("Node1"), Crypto.hash("Node2")] == NetworkLedger.list_node_transactions()

    assert [
             %Node{
               ip: {127, 0, 0, 1},
               port: 5000,
               first_public_key: "Node0",
               last_public_key: "Node1"
             }
           ] = NetworkLedger.list_nodes()

    assert 2 = NetworkLedger.count_node_changes("Node0")

    assert {:ok, Crypto.hash("NodeSharedSecrets1")} ==
             NetworkLedger.get_last_node_shared_secrets_address()

    assert [Crypto.hash("CodeProposal1")] == NetworkLedger.list_code_proposals_addresses()
  end
end
