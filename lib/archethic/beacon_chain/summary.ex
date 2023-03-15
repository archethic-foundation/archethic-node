defmodule Archethic.BeaconChain.Summary do
  @moduledoc """
  Represent a beacon chain summary generated after each summary phase
  containing transactions, node updates
  """

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.Slot.EndOfNodeSync

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  alias Archethic.Crypto

  @availability_adding_time :archethic
                            |> Application.compile_env!(Archethic.SelfRepair.Scheduler)
                            |> Keyword.fetch!(:availability_application)

  defstruct [
    :subset,
    :summary_time,
    availability_adding_time: @availability_adding_time,
    transaction_attestations: [],
    node_availabilities: <<>>,
    node_average_availabilities: [],
    end_of_node_synchronizations: [],
    version: 1
  ]

  @type t :: %__MODULE__{
          subset: binary(),
          summary_time: DateTime.t(),
          availability_adding_time: non_neg_integer(),
          transaction_attestations: list(ReplicationAttestation.t()),
          node_availabilities: bitstring(),
          node_average_availabilities: list(float()),
          end_of_node_synchronizations: list(Crypto.key()),
          version: pos_integer()
        }

  @doc """
  Generate a summary from a list of beacon chain slot transactions

  The transaction summaries listed in the beacon chain will be appended and the P2P view will be aggregated.

  This P2P view is composed by two metrics:
  - availability
  - average of the availability

  The `availability` is determined by aggregating the available sample in the chain and using a `mode` to determine if the node was mostly available
  The `average availability` is a ratio from the times a node was available

  Each node is identified in a position based on the sorting of the public keys

  However node can join the network at any times, and their availability can be detected during the summary from the old and new ones.

  ## Examples

    ### Aggregate the P2P view and the transaction summaries for a static list of nodes during the beacon chain

      iex> :ets.new(:archethic_slot_timer, [:named_table, :public, read_concurrency: true])
      ...> :ets.insert(:archethic_slot_timer, {:interval, "0 */10 * * * * *"})
      ...> Summary.aggregate_slots(%Summary{}, [
      ...>  %Slot{
      ...>   slot_time: ~U[2020-06-25 15:12:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>       transaction_summary: %TransactionSummary{
      ...>         address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>              99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>         type: :transfer,
      ...>         timestamp: ~U[2020-06-25 15:11:53Z],
      ...>         fee: 10_000_000
      ...>       }
      ...>     }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<600::16, 0::16, 600::16>>}
      ...>  },
      ...>  %Slot{
      ...>   slot_time: ~U[2020-06-25 15:12:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>       transaction_summary: %TransactionSummary{
      ...>         address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>              99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>         type: :transfer,
      ...>         timestamp: ~U[2020-06-25 15:11:53Z],
      ...>         fee: 10_000_000
      ...>       }
      ...>     }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<600::16, 0::16, 600::16>>}
      ...>  },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 100::16, 600::16>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 100::16, 600::16>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 200::16, 470::16>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 500::16, 0::16>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<0::16, 600::16, 300::16>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 600::16, 300::16>>}, slot_time: ~U[2020-06-25 15:11:30Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 600::16, 300::16>>}, slot_time: ~U[2020-06-25 15:11:30Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<0::16, 600::16, 300::16>>}, slot_time: ~U[2020-06-25 15:11:30Z] }
      ...> ], [
      ...>   %Node{first_public_key: "key1", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key2", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key3", enrollment_date: ~U[2020-06-25 15:11:00Z]}
      ...> ])
      %Summary{
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary: %TransactionSummary{
                  address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                  type: :transfer,
                  timestamp: ~U[2020-06-25 15:11:53Z],
                  fee: 10_000_000
              }
            }
          ],
        node_availabilities: <<1::1, 0::1, 1::1>>,
        node_average_availabilities: [1.0, 0.4601449275362319, 0.7717391304347827]
      }

    ### Aggregate the P2P view and the transaction attestations with new node joining during the beacon chain epoch

      iex> :ets.new(:archethic_slot_timer, [:named_table, :public, read_concurrency: true])
      ...> :ets.insert(:archethic_slot_timer, {:interval, "0 */10 * * * * *"})
      ...> Summary.aggregate_slots(%Summary{}, [
      ...>  %Slot{
      ...>   slot_time: ~U[2020-06-25 15:12:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>        transaction_summary: %TransactionSummary{
      ...>          address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>               99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>          type: :transfer,
      ...>          timestamp: ~U[2020-06-25 15:11:53Z],
      ...>          fee: 10_000_000
      ...>        }
      ...>     }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<0::16, 0::16, 600::16, 600::16>>}
      ...>  },
      ...>  %Slot{
      ...>   slot_time: ~U[2020-06-25 15:12:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>        transaction_summary: %TransactionSummary{
      ...>          address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>               99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>          type: :transfer,
      ...>          timestamp: ~U[2020-06-25 15:11:53Z],
      ...>          fee: 10_000_000
      ...>        }
      ...>     }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<0::16, 0::16, 600::16, 600::16>>}
      ...>  },
      ...>  %Slot{ p2p_view: %{availabilities: <<200::16, 300::16, 600::16, 600::16>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<200::16, 200::16, 600::16, 600::16>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 200::16, 600::16, 600::16>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 450::16, 200::16>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 450::16, 200::16>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<600::16, 600::16, 0::16>>}, slot_time: ~U[2020-06-25 15:11:30Z] }
      ...> ], [
      ...>   %Node{first_public_key: "key1", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key2", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key3", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key4", enrollment_date: ~U[2020-06-25 15:11:45Z]}
      ...> ])
      %Summary{
        transaction_attestations: [
          %ReplicationAttestation {
            transaction_summary: %TransactionSummary{
              address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
              type: :transfer,
              timestamp: ~U[2020-06-25 15:11:53Z],
              fee: 10_000_000
            }
          }
        ],
        node_availabilities: <<1::1, 0::1, 1::1, 1::1>>,
        node_average_availabilities: [0.5434782608695653, 0.48369565217391314, 0.6231884057971014, 1.0]
      }
  """
  @spec aggregate_slots(
          summary :: t(),
          beacon_chain_slots :: Enumerable.t() | list(Slot.t()),
          subset_nodes :: list(Node.t())
        ) :: t()
  def aggregate_slots(summary = %__MODULE__{}, slots, subset_nodes) do
    summary
    |> aggregate_transaction_attestations(slots)
    |> aggregate_availabilities(slots, subset_nodes)
    |> aggregate_end_of_sync(slots)
  end

  defp aggregate_transaction_attestations(summary = %__MODULE__{}, slots) do
    transaction_attestations =
      slots
      |> Stream.flat_map(& &1.transaction_attestations)
      |> ReplicationAttestation.reduce_confirmations()
      |> Enum.sort_by(
        fn %ReplicationAttestation{
             transaction_summary: %TransactionSummary{timestamp: timestamp}
           } ->
          timestamp
        end,
        {:asc, DateTime}
      )

    %{summary | transaction_attestations: transaction_attestations}
  end

  defp aggregate_availabilities(summary = %__MODULE__{}, slots, node_list) do
    nb_nodes = length(node_list)

    %{availabilities: availabilities, average_availabilities: average_availabilities} =
      slots
      |> Enum.reduce(
        %{},
        &reduce_slot_availabilities(&1, &2, node_list)
      )
      |> Enum.reduce(
        %{
          availabilities: <<0::size(nb_nodes)>>,
          average_availabilities:
            if nb_nodes > 0 do
              Enum.map(1..nb_nodes, fn _ -> 1.0 end)
            else
              []
            end
        },
        &reduce_summary_availabilities/2
      )

    %{
      summary
      | node_availabilities: availabilities,
        node_average_availabilities: average_availabilities
    }
  end

  defp aggregate_end_of_sync(summary = %__MODULE__{}, slots) do
    end_of_node_synchronizations =
      slots
      |> Enum.flat_map(fn %Slot{end_of_node_synchronizations: nodes_end_of_sync} ->
        nodes_end_of_sync
        |> Enum.map(fn %EndOfNodeSync{public_key: public_key} -> public_key end)
      end)
      |> Enum.uniq()

    %{
      summary
      | end_of_node_synchronizations: end_of_node_synchronizations
    }
  end

  defp reduce_slot_availabilities(
         %Slot{slot_time: slot_time, p2p_view: %{availabilities: availabilities_bin}},
         acc,
         node_list
       ) do
    node_list_subset_time = node_list_at_slot_time(node_list, slot_time)

    availabilities = for <<availability_time::16 <- availabilities_bin>>, do: availability_time

    availabilities
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {availability_time, i}, acc ->
      node = Enum.at(node_list_subset_time, i)
      node_pos = Enum.find_index(node_list, &(&1.first_public_key == node.first_public_key))

      availability_by_slot =
        Map.get(acc, node_pos, %{})
        |> Map.update(slot_time, [availability_time], &[availability_time | &1])

      Map.put(acc, node_pos, availability_by_slot)
    end)
  end

  defp node_list_at_slot_time(node_list, slot_time) do
    node_list
    |> Enum.filter(fn %Node{
                        enrollment_date: enrollment_date
                      } ->
      DateTime.diff(enrollment_date, slot_time) <= 0
    end)
    |> Enum.sort_by(& &1.first_public_key)
  end

  defp reduce_summary_availabilities(
         {node_index, availabilities},
         acc
       ) do
    # First, do a median for each slot
    # Then do a wheighted mean of the result
    map =
      availabilities
      |> Enum.sort_by(fn {slot_time, _} -> slot_time end, {:asc, DateTime})
      |> Enum.map(fn {_, availabilities} -> Utils.median(availabilities) end)
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {slot_availability_time, slot_index}, acc ->
        # 1,0 -> 1,1 -> 1,2 ...
        # Weight for 144th slot = 15.3
        weight = 1 + slot_index / 10
        weighted_availability_time = slot_availability_time * weight

        acc
        |> Map.update(
          :total_availability_time,
          weighted_availability_time,
          &(&1 + weighted_availability_time)
        )
        |> Map.update(:total_weight, weight, &(&1 + weight))
      end)

    availability_time = Map.get(map, :total_availability_time) / Map.get(map, :total_weight)
    avg_availability = availability_time / SlotTimer.get_time_interval()
    # TODO We may change the value where the node is considered as available
    # to get only stable nodes like avg_availability > 0.85
    available? = avg_availability > 0.5

    acc
    |> Map.update!(:availabilities, fn bitstring ->
      if available? do
        Utils.set_bitstring_bit(bitstring, node_index)
      else
        bitstring
      end
    end)
    |> Map.update!(
      :average_availabilities,
      &List.replace_at(&1, node_index, avg_availability)
    )
  end

  @doc """
  Serialize a beacon summary into binary format

  ## Examples

      iex> %Summary{
      ...>   subset: <<0>>,
      ...>   summary_time: ~U[2021-01-20 00:00:00Z],
      ...>   availability_adding_time: 900,
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>       transaction_summary: %TransactionSummary{
      ...>          address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>            99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>          timestamp: ~U[2020-06-25 15:11:53Z],
      ...>          type: :transfer,
      ...>          movements_addresses: [],
      ...>          fee: 10_000_000,
      ...>          validation_stamp_checksum: <<17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
      ...>            167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
      ...>       },
      ...>       confirmations: [{0, <<255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
      ...>         170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
      ...>         210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
      ...>         213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253>>}]
      ...>     }
      ...>   ],
      ...>   node_availabilities: <<1::1, 1::1>>,
      ...>   node_average_availabilities: [1.0, 1.0],
      ...>   end_of_node_synchronizations: [<<0, 1, 190, 20, 188, 141, 156, 135, 91, 37, 96, 187, 27, 24, 41, 130, 118,
      ...>    93, 43, 240, 229, 97, 227, 194, 31, 97, 228, 78, 156, 194, 154, 74, 160, 104>>]
      ...> }
      ...> |> Summary.serialize()
      <<
      # Version
      1,
      # Subset
      0,
      # Summary time
      96, 7, 114, 128,
      # Nb transactions attestations
      1, 1,
      # Replication attestation version
      1,
      # Transaction summary version
      1,
      # Transaction address
      0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      # Timestamp
      0, 0, 1, 114, 236, 9, 2, 168,
      # Type (transfer)
      253,
      # Fee
      0, 0, 0, 0, 0, 152, 150, 128,
      # Nb movement addresses
      1, 0,
      # Validation stamp checksum
      17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
      167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219,
      # Nb confirmations
      1,
      # Replication storage node position
      0,
      # Replication Storage node signature size
      64,
      # Replication storage node signature
      255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
      170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
      210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
      213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253,
      # Nb Node availabilities
      0, 2,
      # Availabilities
      1::1, 1::1,
      # Average availabilities
      100,
      100,
      # Nb node end of sync
      1, 1,
      # Node end of sync
      0, 1, 190, 20, 188, 141, 156, 135, 91, 37, 96, 187, 27, 24, 41, 130, 118,
      93, 43, 240, 229, 97, 227, 194, 31, 97, 228, 78, 156, 194, 154, 74, 160, 104,
      # Availability adding time
      3, 132
      >>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        version: version,
        subset: subset,
        summary_time: summary_time,
        transaction_attestations: transaction_attestations,
        node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities,
        end_of_node_synchronizations: end_of_node_synchronizations,
        availability_adding_time: availability_adding_time
      }) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_binary()

    node_average_availabilities_bin =
      node_average_availabilities
      |> Enum.map(fn avg ->
        <<trunc(avg * 100)::8>>
      end)
      |> :erlang.list_to_binary()

    end_of_node_synchronizations_bin = :erlang.list_to_binary(end_of_node_synchronizations)

    encoded_transaction_attestations_len = length(transaction_attestations) |> VarInt.from_value()

    encoded_end_of_node_synchronizations_len =
      length(end_of_node_synchronizations) |> VarInt.from_value()

    <<version::8, subset::binary, DateTime.to_unix(summary_time)::32,
      encoded_transaction_attestations_len::binary, transaction_attestations_bin::binary,
      bit_size(node_availabilities)::16, node_availabilities::bitstring,
      node_average_availabilities_bin::binary, encoded_end_of_node_synchronizations_len::binary,
      end_of_node_synchronizations_bin::binary, availability_adding_time::16>>
  end

  @doc """
  Deserialize an encoded Beacon Summary

  ## Examples

      iex> << 1, 0, 96, 7, 114, 128, 1, 1, 1, 1, 0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...> 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12, 0, 0, 1, 114, 236, 9, 2, 168,
      ...> 253, 0, 0, 0, 0, 0, 152, 150, 128, 1, 0, 17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
      ...> 167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219, 1, 0, 64,
      ...> 255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
      ...> 170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
      ...> 210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
      ...> 213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253, 0, 2, 1::1, 1::1, 100, 100, 1, 1,
      ...> 0, 1, 190, 20, 188, 141, 156, 135, 91, 37, 96, 187, 27, 24, 41, 130, 118,
      ...> 93, 43, 240, 229, 97, 227, 194, 31, 97, 228, 78, 156, 194, 154, 74, 160, 104, 3, 132 >>
      ...> |> Summary.deserialize()
      {
      %Summary{
          subset: <<0>>,
          summary_time: ~U[2021-01-20 00:00:00Z],
          availability_adding_time: 900,
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary:  %TransactionSummary{
                  address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                  99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                  timestamp: ~U[2020-06-25 15:11:53.000Z],
                  type: :transfer,
                  movements_addresses: [],
                  fee: 10_000_000,
                  validation_stamp_checksum: <<17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
                    167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
              },
              confirmations: [{0, <<255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
                170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
                210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
                213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253>>}]
            }
          ],
          node_availabilities: <<1::1, 1::1>>,
          node_average_availabilities: [1.0, 1.0],
          end_of_node_synchronizations: [<<0, 1, 190, 20, 188, 141, 156, 135, 91, 37, 96, 187, 27, 24, 41, 130, 118,
          93, 43, 240, 229, 97, 227, 194, 31, 97, 228, 78, 156, 194, 154, 74, 160, 104>>]
      },
      ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<1::8, subset::8, summary_timestamp::32, rest::bitstring>>) do
    {nb_transaction_attestations, rest} = rest |> VarInt.get_value()

    {transaction_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    <<nb_availabilities::16, availabilities::bitstring-size(nb_availabilities), rest::bitstring>> =
      rest

    <<node_average_availabilities_bin::binary-size(nb_availabilities), rest::bitstring>> = rest

    {nb_end_of_sync, rest} = rest |> VarInt.get_value()

    {end_of_node_synchronizations, <<availability_adding_time::16, rest::bitstring>>} =
      Utils.deserialize_public_key_list(rest, nb_end_of_sync, [])

    node_average_availabilities = for <<avg::8 <- node_average_availabilities_bin>>, do: avg / 100

    {%__MODULE__{
       subset: <<subset>>,
       summary_time: DateTime.from_unix!(summary_timestamp),
       availability_adding_time: availability_adding_time,
       transaction_attestations: transaction_attestations,
       node_availabilities: availabilities,
       node_average_availabilities: node_average_availabilities,
       end_of_node_synchronizations: end_of_node_synchronizations
     }, rest}
  end
end
