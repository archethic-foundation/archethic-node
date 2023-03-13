defmodule Archethic.BeaconChainTest do
  use ArchethicCase

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.BeaconChain.Subset
  alias Archethic.BeaconChain.Subset.SummaryCache
  alias Archethic.BeaconChain.SubsetRegistry
  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  doctest Archethic.BeaconChain

  import Mox

  setup do
    start_supervised!({SlotTimer, interval: "0 0 * * * *"})
    start_supervised!({SummaryTimer, interval: "0 0 * * * *"})
    Enum.map(BeaconChain.list_subsets(), &start_supervised({Subset, subset: &1}, id: &1))
    Enum.each(BeaconChain.list_subsets(), &Subset.start_link(subset: &1))
    :ok
  end

  test "all_subsets/0 should return 256 subsets" do
    assert Enum.map(0..255, &:binary.encode_unsigned(&1)) == BeaconChain.list_subsets()
  end

  test "summary_transaction_address/2 should return a address using the storage nonce a subset and a date" do
    assert <<0, 0, 248, 132, 24, 218, 125, 28, 234, 1, 67, 220, 132, 122, 57, 168, 19, 36, 154,
             81, 148, 222, 244, 124, 19, 175, 134, 199, 110, 21, 100, 49, 181,
             210>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-13 00:00:00Z])

    assert <<0, 0, 15, 150, 229, 125, 70, 53, 7, 122, 235, 195, 14, 164, 62, 53, 217, 55, 181, 13,
             112, 203, 123, 18, 150, 174, 104, 244, 199, 231, 184, 228, 118,
             40>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-14 00:00:00Z])
  end

  test "add_end_of_node_sync/2 should register a end of synchronization inside a subset" do
    public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    assert :ok = BeaconChain.add_end_of_node_sync(public_key, DateTime.utc_now())

    <<_::8, _::8, subset::binary-size(1), _::binary>> = public_key
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{
      current_slot: %Slot{end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]}
    } = :sys.get_state(pid)
  end

  describe "load_slot/1" do
    test "should fetch the transaction chain from the beacon involved nodes" do
      SummaryCache.start_link()
      File.mkdir_p!(Utils.mut_dir())

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        last_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10)
      })

      slot = %Slot{
        subset: <<0>>,
        slot_time: SlotTimer.previous_slot(DateTime.utc_now()),
        transaction_attestations: []
      }

      assert :ok = BeaconChain.load_slot(slot)

      Process.sleep(500)

      assert [%Slot{subset: <<0>>}] = SummaryCache.pop_slots(<<0>>)
    end
  end

  describe "fetch_and_aggregate_summaries/1" do
    setup do
      summary_time = ~U[2021-01-22 16:12:58Z]

      node_keypair1 = Crypto.derive_keypair("node_seed", 1)
      node_keypair2 = Crypto.derive_keypair("node_seed", 2)
      node_keypair3 = Crypto.derive_keypair("node_seed", 3)
      node_keypair4 = Crypto.derive_keypair("node_seed", 4)

      node1 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair1, 0),
        last_public_key: elem(node_keypair1, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        availability_history: <<1::1>>
      }

      node2 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair2, 0),
        last_public_key: elem(node_keypair2, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        availability_history: <<1::1>>
      }

      node3 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair3, 0),
        last_public_key: elem(node_keypair3, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        availability_history: <<1::1>>
      }

      node4 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair4, 0),
        last_public_key: elem(node_keypair4, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        availability_history: <<1::1>>
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)
      P2P.add_and_connect_node(node3)
      P2P.add_and_connect_node(node4)

      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        available?: false
      })

      {:ok, %{summary_time: summary_time, nodes: [node1, node2, node3, node4]}}
    end

    test "should download the beacon summary", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      addr1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      tx_summary = %TransactionSummary{
        address: addr1,
        timestamp: DateTime.utc_now(),
        type: :transfer,
        fee: 100_000_000
      }

      nodes = P2P.authorized_and_available_nodes() |> Enum.sort_by(& &1.first_public_key)

      beacon_summary = %Summary{
        subset: "A",
        summary_time: summary_time,
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: tx_summary,
            confirmations:
              [node1, node2, node3, node4]
              |> Enum.with_index(1)
              |> Enum.map(fn {node, index} ->
                node_index = Enum.find_index(nodes, &(&1 == node))
                {_, pv} = Crypto.derive_keypair("node_seed", index)
                {node_index, Crypto.sign(TransactionSummary.serialize(tx_summary), pv)}
              end)
          }
        ]
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetBeaconSummaries{}, _ ->
          {:ok, %BeaconSummaryList{summaries: [beacon_summary]}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, tx_summary}
      end)

      %SummaryAggregate{replication_attestations: attestations} =
        BeaconChain.fetch_and_aggregate_summaries(
          summary_time,
          P2P.authorized_and_available_nodes()
        )
        |> SummaryAggregate.aggregate()

      assert [addr1] == Enum.map(attestations, & &1.transaction_summary.address)
    end

    test "should find other beacon summaries and aggregate missing summaries", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      addr1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      addr2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      storage_nodes = Election.chain_storage_nodes(addr1, P2P.authorized_and_available_nodes())

      tx_summary = %TransactionSummary{
        address: addr1,
        timestamp: DateTime.utc_now(),
        type: :transfer,
        fee: 100_000_000
      }

      summary_v1 = %Summary{
        subset: "A",
        summary_time: summary_time,
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: tx_summary,
            confirmations:
              [node1, node2, node3, node4]
              |> Enum.with_index(1)
              |> Enum.map(fn {node, index} ->
                node_index = Enum.find_index(storage_nodes, &(&1 == node))
                {_, pv} = Crypto.derive_keypair("node_seed", index)
                {node_index, Crypto.sign(TransactionSummary.serialize(tx_summary), pv)}
              end)
          }
        ]
      }

      summary_v2 = %Summary{
        subset: "A",
        summary_time: summary_time,
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: tx_summary,
            confirmations:
              [node1, node2, node3, node4]
              |> Enum.with_index(1)
              |> Enum.map(fn {node, index} ->
                node_index = Enum.find_index(storage_nodes, &(&1 == node))
                {_, pv} = Crypto.derive_keypair("node_seed", index)
                {node_index, Crypto.sign(TransactionSummary.serialize(tx_summary), pv)}
              end)
          },
          %ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address: addr2,
              timestamp: DateTime.utc_now(),
              type: :transfer,
              fee: 100_000_000
            },
            confirmations:
              [node1, node2, node3, node4]
              |> Enum.with_index(1)
              |> Enum.map(fn {node, index} ->
                node_index = Enum.find_index(storage_nodes, &(&1 == node))
                {_, pv} = Crypto.derive_keypair("node_seed", index)
                {node_index, Crypto.sign(TransactionSummary.serialize(tx_summary), pv)}
              end)
          }
        ]
      }

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetBeaconSummaries{}, _ ->
          {:ok, %BeaconSummaryList{summaries: [summary_v1]}}

        ^node2, %GetBeaconSummaries{}, _ ->
          {:ok, %BeaconSummaryList{summaries: [summary_v2]}}

        ^node3, %GetBeaconSummaries{}, _ ->
          {:ok, %BeaconSummaryList{summaries: [summary_v1]}}

        ^node4, %GetBeaconSummaries{}, _ ->
          {:ok, %BeaconSummaryList{summaries: [summary_v2]}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, tx_summary}
      end)

      %SummaryAggregate{replication_attestations: attestations} =
        BeaconChain.fetch_and_aggregate_summaries(
          summary_time,
          P2P.authorized_and_available_nodes()
        )
        |> SummaryAggregate.aggregate()

      transaction_addresses = Enum.map(attestations, & &1.transaction_summary.address)

      assert Enum.all?(transaction_addresses, &(&1 in [addr1, addr2]))
    end

    test "should find other beacon summaries and accumulate node P2P views", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>,
        end_of_node_synchronizations: []
      }

      summary_v2 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 1::1>>,
        end_of_node_synchronizations: []
      }

      summary_v3 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 0::1, 1::1>>,
        end_of_node_synchronizations: []
      }

      summary_v4 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>,
        end_of_node_synchronizations: []
      }

      subset_address = Crypto.derive_beacon_chain_address("A", summary_time, true)

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v1]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}

        ^node2, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v2]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}

        ^node3, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v3]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}

        ^node4, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v4]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}
      end)

      assert %SummaryAggregate{
               p2p_availabilities: %{"A" => %{node_availabilities: node_availabilities}}
             } =
               BeaconChain.fetch_and_aggregate_summaries(
                 summary_time,
                 P2P.authorized_and_available_nodes()
               )
               |> SummaryAggregate.aggregate()

      assert <<1::1, 1::1, 1::1>> == node_availabilities
    end

    test "should find other beacon summaries and accumulate node P2P avg availabilities", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_average_availabilities: [1.0, 0.9, 1.0, 1.0]
      }

      summary_v2 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_average_availabilities: [0.90, 0.9, 1.0, 1.0]
      }

      summary_v3 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_average_availabilities: [0.8, 0.9, 0.7, 1.0]
      }

      summary_v4 = %Summary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>,
        node_average_availabilities: [1.0, 0.5, 1.0, 0.4]
      }

      subset_address = Crypto.derive_beacon_chain_address("A", summary_time, true)

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v1]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}

        ^node2, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v2]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}

        ^node3, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v3]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}

        ^node4, %GetBeaconSummaries{addresses: addresses}, _ ->
          summaries =
            if subset_address in addresses do
              [summary_v4]
            else
              []
            end

          {:ok, %BeaconSummaryList{summaries: summaries}}
      end)

      assert %SummaryAggregate{
               p2p_availabilities: %{
                 "A" => %{node_average_availabilities: node_average_availabilities}
               }
             } =
               BeaconChain.fetch_and_aggregate_summaries(
                 summary_time,
                 P2P.authorized_and_available_nodes()
               )
               |> SummaryAggregate.aggregate()

      assert [0.925, 0.8, 0.925, 0.85] == node_average_availabilities
    end
  end
end
