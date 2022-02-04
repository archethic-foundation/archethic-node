defmodule ArchEthic.BeaconChain.Summary do
  @moduledoc """
  Represent a beacon chain summary generated after each summary phase
  containing transactions, node updates
  """

  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Subset.P2PSampling

  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.TransactionSummary

  alias ArchEthic.Utils

  defstruct [
    :subset,
    :summary_time,
    transaction_attestations: [],
    node_availabilities: <<>>,
    node_average_availabilities: [],
    version: 1
  ]

  @type t :: %__MODULE__{
          subset: binary(),
          summary_time: DateTime.t(),
          transaction_attestations: list(ReplicationAttestation.t()),
          node_availabilities: bitstring(),
          node_average_availabilities: list(float()),
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

      iex> Summary.aggregate_slots(%Summary{}, [
      ...>  %Slot{
      ...>   slot_time: ~U[2020-06-25 15:12:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>       transaction_summary: %TransactionSummary{
      ...>         address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>              99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>         type: :transfer,
      ...>         timestamp: ~U[2020-06-25 15:11:53Z]
      ...>       }
      ...>     }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<1::1, 0::1, 1::1>>}
      ...>  },
      ...>  %Slot{ p2p_view: %{availabilities: <<0::1, 1::1, 1::1>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<1::1, 1::1, 0::1>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<1::1, 1::1, 0::1>>}, slot_time: ~U[2020-06-25 15:11:30Z] }
      ...> ], [
      ...>   %Node{first_public_key: "key1", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key2", enrollment_date: ~U[2020-06-25 15:11:00Z]},
      ...>   %Node{first_public_key: "key3", enrollment_date: ~U[2020-06-25 15:11:00Z]}
      ...> ])
      %Summary{
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary: %TransactionSummary{
                  address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                  type: :transfer,
                  timestamp: ~U[2020-06-25 15:11:53Z]
              }
            }
          ],
        node_availabilities: <<1::1, 1::1, 1::1>>,
        node_average_availabilities: [0.75, 0.75, 0.50]
      }

    ### Aggregate the P2P view and the transaction attestations with new node joining during the beacon chain epoch

      iex> Summary.aggregate_slots(%Summary{}, [
      ...>  %Slot{
      ...>   slot_time: ~U[2020-06-25 15:12:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>        transaction_summary: %TransactionSummary{
      ...>          address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>               99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>          type: :transfer,
      ...>          timestamp: ~U[2020-06-25 15:11:53Z]
      ...>        }
      ...>     }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<1::1, 0::1, 1::1, 1::1>>}
      ...>  },
      ...>  %Slot{ p2p_view: %{availabilities: <<0::1, 1::1, 1::1, 1::1>>}, slot_time: ~U[2020-06-25 15:11:50Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<1::1, 1::1, 0::1>>}, slot_time: ~U[2020-06-25 15:11:40Z] },
      ...>  %Slot{ p2p_view: %{availabilities: <<1::1, 1::1, 0::1>>}, slot_time: ~U[2020-06-25 15:11:30Z] }
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
              address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
              type: :transfer,
              timestamp: ~U[2020-06-25 15:11:53Z]
            }
          }
        ],
        node_availabilities: <<1::1, 1::1, 1::1, 1::1>>,
        node_average_availabilities: [0.75, 0.75, 0.50, 1.0]
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
  end

  defp aggregate_transaction_attestations(summary = %__MODULE__{}, slots) do
    transaction_attestations =
      slots
      |> Enum.flat_map(& &1.transaction_attestations)
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
        &reduce_slot_availabities(&1, &2, node_list)
      )
      |> Enum.reduce(
        %{
          availabilities: <<0::size(nb_nodes)>>,
          average_availabilities: Enum.map(1..nb_nodes, fn _ -> 1.0 end)
        },
        &reduce_summary_availabilities/2
      )

    %{
      summary
      | node_availabilities: availabilities,
        node_average_availabilities: average_availabilities
    }
  end

  defp reduce_slot_availabities(
         %Slot{slot_time: slot_time, p2p_view: %{availabilities: availabilities}},
         acc,
         node_list
       ) do
    node_list_subset_time = node_list_at_slot_time(node_list, slot_time)

    availabilities
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {availability, i}, acc ->
      node = Enum.at(node_list_subset_time, i)
      node_pos = Enum.find_index(node_list, &(&1.first_public_key == node.first_public_key))

      Map.update(acc, node_pos, [availability], &[availability | &1])
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
    frequencies = Enum.frequencies(availabilities)
    online_frequencies = Map.get(frequencies, 1, 0)
    offline_frequencies = Map.get(frequencies, 0, 0)

    available? = online_frequencies >= offline_frequencies
    avg_availability = online_frequencies / length(availabilities)

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
  Cast a beacon's slot into a summary
  """
  @spec from_slot(Slot.t()) :: t()
  def from_slot(%Slot{
        subset: subset,
        slot_time: slot_time,
        transaction_attestations: transaction_attestations
      }) do
    %__MODULE__{
      subset: subset,
      summary_time: slot_time,
      transaction_attestations: transaction_attestations
    }
  end

  @doc """
  Serialize a beacon summary into binary format

  ## Examples

      iex> %Summary{
      ...>   subset: <<0>>,
      ...>   summary_time: ~U[2021-01-20 00:00:00Z],
      ...>   transaction_attestations: [
      ...>     %ReplicationAttestation {
      ...>       transaction_summary: %TransactionSummary{
      ...>          address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>            99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>          timestamp: ~U[2020-06-25 15:11:53Z],
      ...>          type: :transfer,
      ...>          movements_addresses: []
      ...>       },
      ...>       confirmations: [{0, <<255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
      ...>         170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
      ...>         210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
      ...>         213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253>>}]
      ...>     }
      ...>   ],
      ...>   node_availabilities: <<1::1, 1::1>>,
      ...>   node_average_availabilities: [1.0, 1.0]
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
      0, 0, 0, 1,
      # Replication attestation version
      1,
      # Transaction address
      0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      # Timestamp
      0, 0, 1, 114, 236, 9, 2, 168,
      # Type (transfer)
      253,
      # Nb movement addresses
      0, 0,
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
      100
      >>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        version: 1,
        subset: subset,
        summary_time: summary_time,
        transaction_attestations: transaction_attestations,
        node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities
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

    <<1::8, subset::binary, DateTime.to_unix(summary_time)::32,
      length(transaction_attestations)::32, transaction_attestations_bin::binary,
      bit_size(node_availabilities)::16, node_availabilities::bitstring,
      node_average_availabilities_bin::binary>>
  end

  @doc """
  Deserialize an encoded Beacon Summary

  ## Examples

      iex> <<1, 0, 96, 7, 114, 128, 0, 0, 0, 1, 1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...> 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...> 0, 0, 1, 114, 236, 9, 2, 168, 253, 0, 0,
      ...> 1, 0, 64, 255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
      ...> 170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
      ...> 210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
      ...> 213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253,
      ...> 0, 2, 1::1, 1::1, 100, 100>>
      ...> |> Summary.deserialize()
      {
      %Summary{
          subset: <<0>>,
          summary_time: ~U[2021-01-20 00:00:00Z],
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary:  %TransactionSummary{
                  address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                  99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                  timestamp: ~U[2020-06-25 15:11:53.000Z],
                  type: :transfer,
                  movements_addresses: []
              },
              confirmations: [{0, <<255, 120, 232, 52, 141, 15, 97, 213, 231, 93, 242, 160, 123, 25, 192, 3, 133,
                170, 197, 102, 148, 208, 119, 130, 225, 102, 130, 96, 223, 61, 36, 76, 229,
                210, 5, 142, 79, 249, 177, 51, 15, 45, 45, 141, 217, 85, 77, 146, 199, 126,
                213, 205, 108, 164, 167, 112, 201, 194, 113, 133, 242, 104, 254, 253>>}]
            }
          ],
          node_availabilities: <<1::1, 1::1>>,
          node_average_availabilities: [1.0, 1.0]
      },
      ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(
        <<1::8, subset::8, summary_timestamp::32, nb_transaction_attestations::32,
          rest::bitstring>>
      ) do
    {transaction_attestations, rest} =
      deserialize_tx_attestations(rest, nb_transaction_attestations, [])

    <<nb_availabilities::16, availabilities::bitstring-size(nb_availabilities), rest::bitstring>> =
      rest

    <<node_average_availabilities_bin::binary-size(nb_availabilities), rest::bitstring>> = rest

    node_average_availabilities = for <<avg::8 <- node_average_availabilities_bin>>, do: avg / 100

    {%__MODULE__{
       subset: <<subset>>,
       summary_time: DateTime.from_unix!(summary_timestamp),
       transaction_attestations: transaction_attestations,
       node_availabilities: availabilities,
       node_average_availabilities: node_average_availabilities
     }, rest}
  end

  defp deserialize_tx_attestations(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_attestations(rest, nb_tx_attestations, acc)
       when length(acc) == nb_tx_attestations do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_attestations(rest, nb_tx_attestations, acc) do
    {tx_attestation, rest} = ReplicationAttestation.deserialize(rest)
    deserialize_tx_attestations(rest, nb_tx_attestations, [tx_attestation | acc])
  end

  @doc """
  Return the list node availabilites by identifying the nodes from the binary list
  """
  @spec get_node_availabilities(t(), list(Node.t())) ::
          list({node :: Node.t(), available? :: boolean(), average_availability :: float()})
  def get_node_availabilities(
        %__MODULE__{
          summary_time: summary_time,
          node_availabilities: node_availabilities,
          node_average_availabilities: node_average_availabilities,
          subset: subset
        },
        node_list
      ) do
    node_list = Enum.filter(node_list, &(DateTime.diff(&1.enrollment_date, summary_time) <= 0))

    subset_node_list = P2PSampling.list_nodes_to_sample(subset, node_list)

    node_availabilities
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.map(fn {available_bit, index} ->
      node = Enum.at(subset_node_list, index)
      avg_availability = Enum.at(node_average_availabilities, index)

      case available_bit do
        1 ->
          {node, true, avg_availability}

        0 ->
          {node, false, avg_availability}
      end
    end)
  end

  @doc """
  Determine if the summary is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{
        transaction_attestations: [],
        node_availabilities: <<>>,
        node_average_availabilities: []
      }),
      do: true

  def empty?(_), do: false
end
