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

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.GetCurrentReplicationsAttestations
  alias Archethic.P2P.Message.GetCurrentReplicationsAttestationsResponse
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.P2P.Message.GetCurrentSummaries
  alias Archethic.P2P.Message.TransactionSummaryList
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  doctest Archethic.BeaconChain

  import ArchethicCase
  import Mox
  import Mock

  setup do
    Application.put_env(:archethic, SlotTimer, interval: "0 0 * * * *")
    Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * * *")

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
    public_key = random_address()

    assert :ok = BeaconChain.add_end_of_node_sync(public_key, DateTime.utc_now())

    <<_::8, _::8, subset::binary-size(1), _::binary>> = public_key
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{
      current_slot: %Slot{end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]}
    } = :sys.get_state(pid)
  end

  describe "load_slot/1" do
    test "should add slot in summary cache" do
      SummaryCache.start_link()
      File.mkdir_p!(Utils.mut_dir())

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
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

      assert :ok = BeaconChain.load_slot(slot, Crypto.first_node_public_key())

      Process.sleep(500)

      assert [{%Slot{subset: <<0>>}, _}] =
               SummaryCache.stream_current_slots(<<0>>) |> Enum.to_list()
    end
  end

  describe "fetch_and_aggregate_summaries/1" do
    setup_with_mocks [
      {ReplicationAttestation, [:passthrough], validate: fn _ -> :ok end}
    ] do
      summary_time = ~U[2021-01-22 16:12:58Z]

      node1 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: random_address()
      }

      node2 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: random_address()
      }

      node3 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: random_address()
      }

      node4 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: random_address()
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

    test "should download the beacon summary", %{summary_time: summary_time} do
      addr1 = random_address()

      tx_summary = %TransactionSummary{
        address: addr1,
        timestamp: DateTime.utc_now(),
        type: :transfer,
        fee: 100_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      attestation = %ReplicationAttestation{transaction_summary: tx_summary, confirmations: []}

      beacon_summary = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        transaction_attestations: [attestation]
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

      assert_called(ReplicationAttestation.validate(attestation))
      assert [addr1] == Enum.map(attestations, & &1.transaction_summary.address)
    end

    test "should find other beacon summaries and aggregate missing summaries", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      addr1 = random_address()
      addr2 = random_address()

      tx_summary1 = %TransactionSummary{
        address: addr1,
        timestamp: DateTime.utc_now(),
        type: :transfer,
        fee: 100_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      tx_summary2 = %TransactionSummary{
        address: addr2,
        timestamp: DateTime.utc_now(),
        type: :transfer,
        fee: 100_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      attestation1 = %ReplicationAttestation{transaction_summary: tx_summary1, confirmations: []}
      attestation2 = %ReplicationAttestation{transaction_summary: tx_summary2, confirmations: []}

      summary_v1 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        transaction_attestations: [attestation1]
      }

      summary_v2 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        transaction_attestations: [attestation1, attestation2]
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
      end)

      %SummaryAggregate{replication_attestations: attestations} =
        BeaconChain.fetch_and_aggregate_summaries(
          summary_time,
          P2P.authorized_and_available_nodes()
        )
        |> SummaryAggregate.aggregate()

      transaction_addresses = Enum.map(attestations, & &1.transaction_summary.address)

      assert_called(ReplicationAttestation.validate(attestation1))
      assert_called(ReplicationAttestation.validate(attestation2))

      assert Enum.all?(transaction_addresses, &(&1 in [addr1, addr2]))
    end

    test "should find other beacon summaries and accumulate node P2P views", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1, 0::1>>,
        end_of_node_synchronizations: []
      }

      summary_v2 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 1::1, 0::1>>,
        end_of_node_synchronizations: []
      }

      summary_v3 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 0::1, 1::1, 0::1>>,
        end_of_node_synchronizations: []
      }

      summary_v4 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1, 1::1>>,
        end_of_node_synchronizations: []
      }

      subset_address = Crypto.derive_beacon_chain_address(<<0>>, summary_time, true)

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
               p2p_availabilities: %{<<0>> => %{node_availabilities: node_availabilities}}
             } =
               BeaconChain.fetch_and_aggregate_summaries(
                 summary_time,
                 P2P.authorized_and_available_nodes()
               )
               |> SummaryAggregate.aggregate()

      assert <<1::1, 1::1, 1::1, 0::1>> == node_availabilities
    end

    test "should find other beacon summaries and accumulate node P2P avg availabilities", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_average_availabilities: [1.0, 0.9, 1.0, 1.0]
      }

      summary_v2 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_average_availabilities: [0.90, 0.9, 1.0, 1.0]
      }

      summary_v3 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_average_availabilities: [0.8, 0.9, 0.7, 1.0]
      }

      summary_v4 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>,
        node_average_availabilities: [1.0, 0.5, 1.0, 0.4]
      }

      subset_address = Crypto.derive_beacon_chain_address(<<0>>, summary_time, true)

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
                 <<0>> => %{node_average_availabilities: node_average_availabilities}
               }
             } =
               BeaconChain.fetch_and_aggregate_summaries(
                 summary_time,
                 P2P.authorized_and_available_nodes()
               )
               |> SummaryAggregate.aggregate()

      assert [0.925, 0.8, 0.925, 0.85] == node_average_availabilities
    end

    test "should find other beacon summaries and accumulate network patches", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1>>,
        network_patches: ["ABC", "DEF"]
      }

      summary_v2 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1>>,
        network_patches: ["ABC", "DEF"]
      }

      summary_v3 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1>>,
        network_patches: ["ABC", "DEF"]
      }

      summary_v4 = %Summary{
        subset: <<0>>,
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1>>,
        network_patches: ["ABC", "DEF"]
      }

      subset_address = Crypto.derive_beacon_chain_address(<<0>>, summary_time, true)

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
                 <<0>> => %{
                   network_patches: [
                     ["ABC", "DEF"],
                     ["ABC", "DEF"],
                     ["ABC", "DEF"],
                     ["ABC", "DEF"]
                   ]
                 }
               }
             } =
               BeaconChain.fetch_and_aggregate_summaries(
                 summary_time,
                 P2P.authorized_and_available_nodes()
               )
    end
  end

  describe "get_network_stats/1" do
    test "should get the slot latencies aggregated by node" do
      node1_slots = [
        %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now(),
          p2p_view: %{
            availabilities: <<>>,
            network_stats: [%{latency: 100}, %{latency: 200}, %{latency: 50}]
          }
        },
        %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now() |> DateTime.add(10),
          p2p_view: %{
            availabilities: <<>>,
            network_stats: [%{latency: 110}, %{latency: 150}, %{latency: 70}]
          }
        },
        %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now() |> DateTime.add(20),
          p2p_view: %{
            availabilities: <<>>,
            network_stats: [%{latency: 130}, %{latency: 110}, %{latency: 80}]
          }
        }
      ]

      node2_slots = [
        %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now(),
          p2p_view: %{
            availabilities: <<>>,
            network_stats: [%{latency: 80}, %{latency: 110}, %{latency: 150}]
          }
        },
        %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now() |> DateTime.add(10),
          p2p_view: %{
            availabilities: <<>>,
            network_stats: [%{latency: 70}, %{latency: 140}, %{latency: 100}]
          }
        },
        %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now() |> DateTime.add(20),
          p2p_view: %{
            availabilities: <<>>,
            network_stats: [%{latency: 70}, %{latency: 100}, %{latency: 120}]
          }
        }
      ]

      File.mkdir_p!(Utils.mut_dir())
      SummaryCache.start_link()

      Enum.map(node1_slots, &SummaryCache.add_slot(<<0>>, &1, "node1"))
      Enum.map(node2_slots, &SummaryCache.add_slot(<<0>>, &1, "node2"))

      assert %{
               "node1" => [%{latency: 118}, %{latency: 138}, %{latency: 71}],
               "node2" => [%{latency: 75}, %{latency: 118}, %{latency: 128}]
             } = BeaconChain.get_network_stats(<<0>>)
    end
  end

  describe "list_transactions_summaries_from_current_slot/0" do
    test "should work" do
      now = DateTime.utc_now()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: now |> DateTime.add(-10)
      })

      MockClient
      |> stub(:send_message, fn
        _, %GetCurrentSummaries{}, _ ->
          {:ok,
           %TransactionSummaryList{
             transaction_summaries: [
               %TransactionSummary{
                 address: random_address(),
                 timestamp: now
               }
             ]
           }}
      end)

      summaries = BeaconChain.list_transactions_summaries_from_current_slot()

      # there are 256 subsets, and we query the summaries 10 by 10
      # so we call the GetCurrentSummaries 26 times
      # each call to GetCurrentSummaries return a list of 1 transactionSummary (mock above)
      assert length(summaries) == 26
    end
  end

  describe "list_replications_attestations_from_current_summary/0" do
    test "should return empty if there is nothing yet" do
      assert [] = BeaconChain.list_replications_attestations_from_current_summary()
    end

    test "should return the attestations" do
      now = DateTime.utc_now()

      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: random_public_key(),
          last_public_key: random_public_key(),
          available?: true,
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: now |> DateTime.add(-10)
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          first_public_key: random_public_key(),
          last_public_key: random_public_key(),
          available?: true,
          geo_patch: "BBB",
          network_patch: "BBB",
          authorized?: true,
          authorization_date: now |> DateTime.add(-10)
        }
      ]

      for node <- nodes, do: P2P.add_and_connect_node(node)

      replications_attestations = [random_replication_attestation(now)]

      MockClient
      |> expect(:send_message, length(nodes), fn _, %GetCurrentReplicationsAttestations{}, _ ->
        {:ok,
         %GetCurrentReplicationsAttestationsResponse{
           replications_attestations: replications_attestations
         }}
      end)

      assert ^replications_attestations =
               BeaconChain.list_replications_attestations_from_current_summary()
    end

    test "should merge attestations when different" do
      now = DateTime.utc_now()

      node1 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: now |> DateTime.add(-10)
      }

      node2 = %Node{
        ip: {127, 0, 0, 1},
        port: 3001,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        authorized?: true,
        authorization_date: now |> DateTime.add(-10)
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)

      replication_attestation1 = random_replication_attestation(now)
      replication_attestation2 = random_replication_attestation(now)
      replication_attestation3 = random_replication_attestation(now)
      node1_replications_attestations = [replication_attestation1, replication_attestation2]
      node2_replications_attestations = [replication_attestation1, replication_attestation3]

      MockClient
      |> expect(:send_message, 2, fn
        ^node1, %GetCurrentReplicationsAttestations{}, _ ->
          {:ok,
           %GetCurrentReplicationsAttestationsResponse{
             replications_attestations: node1_replications_attestations
           }}

        ^node2, %GetCurrentReplicationsAttestations{}, _ ->
          {:ok,
           %GetCurrentReplicationsAttestationsResponse{
             replications_attestations: node2_replications_attestations
           }}
      end)

      replications_attestations =
        BeaconChain.list_replications_attestations_from_current_summary()

      assert 3 == length(replications_attestations)
      assert Enum.any?(replications_attestations, &(&1 == replication_attestation1))
      assert Enum.any?(replications_attestations, &(&1 == replication_attestation2))
      assert Enum.any?(replications_attestations, &(&1 == replication_attestation3))
    end
  end

  defp random_replication_attestation(datetime) do
    %ReplicationAttestation{
      version: 2,
      transaction_summary: %TransactionSummary{
        address: random_address(),
        type: :transfer,
        timestamp: datetime,
        fee: 10_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32),
        genesis_address: random_address()
      },
      confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
    }
  end
end
