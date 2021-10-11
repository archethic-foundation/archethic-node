defmodule ArchEthic.BeaconChain.Summary do
  @moduledoc """
  Represent a beacon chain summary generated after each summary phase
  containing transactions, node updates
  """

  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Slot.TransactionSummary

  alias ArchEthic.BeaconChain.Subset.P2PSampling

  alias ArchEthic.Utils

  defstruct [
    :subset,
    :summary_time,
    transaction_summaries: [],
    end_of_node_synchronizations: [],
    node_availabilities: <<>>,
    node_average_availabilities: []
  ]

  @type t :: %__MODULE__{
          subset: binary(),
          summary_time: DateTime.t(),
          transaction_summaries: list(TransactionSummary.t()),
          end_of_node_synchronizations: list(EndOfNodeSync.t()),
          node_availabilities: bitstring(),
          node_average_availabilities: list(float())
        }

  @doc """
  Generate a summary from a list of beacon chain slot transactions

  ## Examples

      iex> Summary.aggregate_slots(%Summary{}, [
      ...>  %Slot{
      ...>   transaction_summaries: [
      ...>     %TransactionSummary{
      ...>       address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>            99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>       type: :transfer,
      ...>       timestamp: ~U[2020-06-25 15:11:53Z]
      ...>      }
      ...>   ],
      ...>   p2p_view: %{ availabilities: <<1::1, 0::1, 1::1>>}
      ...>  },
      ...>  %Slot{ p2p_view: %{availabilities: <<0::1, 1::1, 1::1>>} },
      ...>  %Slot{ p2p_view: %{availabilities: <<1::1, 1::1, 0::1>>} },
      ...>  %Slot{ p2p_view: %{availabilities: <<1::1, 1::1, 0::1>>} }
      ...> ])
      %Summary{
          transaction_summaries: [
            %TransactionSummary{
                address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                type: :transfer,
                timestamp: ~U[2020-06-25 15:11:53Z]
            }
          ],
        node_availabilities: <<1::1, 1::1, 0::1>>,
        node_average_availabilities: [0.75, 0.75, 0.50]
      }
  """
  @spec aggregate_slots(t(), Enumerable.t() | list(Slot.t())) :: t()
  def aggregate_slots(summary = %__MODULE__{}, slots) do
    summary
    |> aggregate_transaction_summaries(slots)
    |> aggregate_end_of_node_synchronizations(slots)
    |> aggregate_availabilities(slots)
  end

  defp aggregate_transaction_summaries(summary = %__MODULE__{}, slots) do
    transaction_summaries =
      slots
      |> Enum.flat_map(& &1.transaction_summaries)
      |> Enum.sort_by(& &1.timestamp)

    %{summary | transaction_summaries: transaction_summaries}
  end

  defp aggregate_end_of_node_synchronizations(summary = %__MODULE__{}, slots) do
    end_of_node_synchronizations =
      slots
      |> Enum.flat_map(& &1.end_of_node_synchronizations)
      |> Enum.sort_by(& &1.timestamp)

    %{summary | end_of_node_synchronizations: end_of_node_synchronizations}
  end

  defp aggregate_availabilities(summary = %__MODULE__{}, slots) do
    nb_slots = Enum.count(slots)
    %Slot{p2p_view: %{availabilities: availabilities}} = Enum.at(slots, 0)
    nb_nodes_sampled = bit_size(availabilities)

    %{
      node_availabilities: node_availabilities,
      node_average_availabilities: node_average_availabilities
    } =
      slots
      |> count_available_times()
      |> Enum.reduce(init_reduce_availabilities(nb_nodes_sampled), fn
        {_, 0}, acc ->
          acc

        {index, nb_times}, acc ->
          avg_availability = nb_times / nb_slots

          if avg_availability > 0.7 do
            acc
            |> Map.update!(:node_availabilities, &Utils.set_bitstring_bit(&1, index))
            |> Map.update!(
              :node_average_availabilities,
              &List.replace_at(&1, index, avg_availability)
            )
          else
            Map.update!(
              acc,
              :node_average_availabilities,
              &List.replace_at(&1, index, avg_availability)
            )
          end
      end)

    %{
      summary
      | node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities
    }
  end

  defp init_reduce_availabilities(nb_nodes_sampled) do
    %{
      node_availabilities: <<0::size(nb_nodes_sampled)>>,
      node_average_availabilities: Enum.map(1..nb_nodes_sampled, fn _ -> 1.0 end)
    }
  end

  defp count_available_times(slots) do
    Enum.reduce(slots, %{}, fn %Slot{p2p_view: %{availabilities: availabilities}}, acc ->
      availabilities
      |> Utils.bitstring_to_integer_list()
      |> Enum.with_index()
      |> Enum.reduce(acc, fn
        {1, index}, acc ->
          Map.update(acc, index, 1, &(&1 + 1))

        {0, _}, acc ->
          acc
      end)
      |> Enum.into(%{})
    end)
  end

  @doc """
  Cast a beacon's slot into a summary
  """
  @spec from_slot(Slot.t()) :: t()
  def from_slot(%Slot{
        subset: subset,
        slot_time: slot_time,
        transaction_summaries: transaction_summaries,
        end_of_node_synchronizations: end_of_node_sync
      }) do
    %__MODULE__{
      subset: subset,
      summary_time: slot_time,
      transaction_summaries: transaction_summaries,
      end_of_node_synchronizations: end_of_node_sync
    }
  end

  @doc """
  Serialize a beacon summary into binary format

  ## Examples

      iex> %Summary{
      ...>   subset: <<0>>,
      ...>   summary_time: ~U[2021-01-20 00:00:00Z],
      ...>   transaction_summaries: [
      ...>     %TransactionSummary{
      ...>        address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>        timestamp: ~U[2020-06-25 15:11:53Z],
      ...>        type: :transfer,
      ...>        movements_addresses: []
      ...>     }
      ...>   ],
      ...>   end_of_node_synchronizations: [
      ...>     %EndOfNodeSync{
      ...>       public_key: <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>        100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
      ...>       timestamp: ~U[2020-06-25 15:11:53Z],
      ...>     }
      ...>   ],
      ...>   node_availabilities: <<1::1, 1::1>>,
      ...>   node_average_availabilities: [1.0, 1.0]
      ...> }
      ...> |> Summary.serialize()
      <<
      # Subset
      0,
      # Summary time
      96, 7, 114, 128,
      # Nb transactions summaries
      0, 0, 0, 1,
      # Transaction address
      0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      # Timestamp
      0, 0, 1, 114, 236, 9, 2, 168,
      # Type (transfer)
      253,
      # Nb movement addresses
      0, 0,
      # Nb nodes synchronizations
      0, 1,
      # Public key
      0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
      # Timestamp
      94, 244, 190, 185,
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
        subset: subset,
        summary_time: summary_time,
        transaction_summaries: transaction_summaries,
        end_of_node_synchronizations: end_of_node_synchronizations,
        node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities
      }) do
    transaction_summaries_bin =
      transaction_summaries
      |> Enum.map(&TransactionSummary.serialize/1)
      |> :erlang.list_to_binary()

    end_of_node_synchronizations_bin =
      end_of_node_synchronizations
      |> Enum.map(&EndOfNodeSync.serialize/1)
      |> :erlang.list_to_binary()

    node_average_availabilities_bin =
      node_average_availabilities
      |> Enum.map(fn avg ->
        <<trunc(avg * 100)::8>>
      end)
      |> :erlang.list_to_binary()

    <<subset::binary, DateTime.to_unix(summary_time)::32, length(transaction_summaries)::32,
      transaction_summaries_bin::binary, length(end_of_node_synchronizations)::16,
      end_of_node_synchronizations_bin::binary, bit_size(node_availabilities)::16,
      node_availabilities::bitstring, node_average_availabilities_bin::binary>>
  end

  @doc """
  Deserialize an encoded Beacon Summary

  ## Examples

      iex> <<0, 96, 7, 114, 128, 0, 0, 0, 1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...> 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...> 0, 0, 1, 114, 236, 9, 2, 168, 253, 0, 0, 0, 1,
      ...> 0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...> 100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
      ...> 94, 244, 190, 185, 0, 2, 1::1, 1::1, 100, 100>>
      ...> |> Summary.deserialize()
      {
      %Summary{
          subset: <<0>>,
          summary_time: ~U[2021-01-20 00:00:00Z],
          transaction_summaries: [
            %TransactionSummary{
                address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
                timestamp: ~U[2020-06-25 15:11:53.000Z],
                type: :transfer,
                movements_addresses: []
            }
          ],
          end_of_node_synchronizations: [ %EndOfNodeSync{
            public_key: <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
            100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
            timestamp: ~U[2020-06-25 15:11:53Z]
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
        <<subset::8, summary_timestamp::32, nb_transaction_summaries::32, rest::bitstring>>
      ) do
    {transaction_summaries, rest} = deserialize_tx_summaries(rest, nb_transaction_summaries, [])

    <<nb_nodes_entries::16, rest::bitstring>> = rest

    {end_of_node_synchronizations, rest} =
      deserialize_end_of_node_synchronizations(rest, nb_nodes_entries, [])

    <<nb_availabilities::16, availabilities::bitstring-size(nb_availabilities), rest::bitstring>> =
      rest

    <<node_average_availabilities_bin::binary-size(nb_availabilities), rest::bitstring>> = rest

    node_average_availabilities = for <<avg::8 <- node_average_availabilities_bin>>, do: avg / 100

    {%__MODULE__{
       subset: <<subset>>,
       summary_time: DateTime.from_unix!(summary_timestamp),
       transaction_summaries: transaction_summaries,
       end_of_node_synchronizations: end_of_node_synchronizations,
       node_availabilities: availabilities,
       node_average_availabilities: node_average_availabilities
     }, rest}
  end

  defp deserialize_tx_summaries(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_summaries(rest, nb_tx_summaries, acc)
       when length(acc) == nb_tx_summaries do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_summaries(rest, nb_tx_summaries, acc) do
    {tx_summary, rest} = TransactionSummary.deserialize(rest)
    deserialize_tx_summaries(rest, nb_tx_summaries, [tx_summary | acc])
  end

  defp deserialize_end_of_node_synchronizations(rest, 0, _acc), do: {[], rest}

  defp deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, acc)
       when length(acc) == nb_end_of_node_synchronizations do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, acc) do
    {end_of_node_sync, rest} = EndOfNodeSync.deserialize(rest)

    deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, [
      end_of_node_sync | acc
    ])
  end

  @doc """
  Return the list node availabilites by identifying the nodes from the binary list
  """
  @spec get_node_availabilities(t()) ::
          list({node :: Node.t(), available? :: boolean(), average_availability :: float()})
  def get_node_availabilities(%__MODULE__{
        node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities,
        subset: subset
      }) do
    node_list = P2PSampling.list_nodes_to_sample(subset)

    Utils.bitstring_to_integer_list(node_availabilities)
    |> Enum.with_index()
    |> Enum.map(fn {available_bit, index} ->
      node = Enum.at(node_list, index)
      avg_availability = Enum.at(node_average_availabilities, index)

      case available_bit do
        1 ->
          {node, true, avg_availability}

        0 ->
          {node, false, avg_availability}
      end
    end)
  end
end
