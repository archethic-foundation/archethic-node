defmodule ArchethicWeb.GraphQLSchema.BeaconChainSummary do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.BeaconChain.Subset.P2PSampling

  @desc """
  [Beacon Chain Summary] represents the beacon chain aggregate for a certain date
  """

  @default_limit 100

  object :beacon_chain_summary do
    field(:version, :integer)
    field(:summary_time, :string)
    field(:availability_adding_time, list_of(:integer))
    field(:p2p_availabilities, :p2p_availabilities)

    field(:transaction_summaries, list_of(:transaction_summary)) do
      arg(:paging_offset, :non_neg_integer)
      arg(:limit, :pos_integer)

      resolve(fn args,
                 %{
                   source: %SummaryAggregate{
                     transaction_summaries: transaction_summaries
                   }
                 } ->
        limit = Map.get(args, :limit, @default_limit)
        paging_offset = Map.get(args, :paging_offset, 0)

        result =
          transaction_summaries
          |> Enum.drop(paging_offset)
          |> Enum.take(limit)

        {:ok, result}
      end)
    end
  end

  @desc """
  [Transaction Summary] Represents transaction header or extract to summarize it
  """
  object :transaction_summary do
    field(:timestamp, :timestamp)
    field(:address, :address)
    field(:movements_addresses, list_of(:address))
    field(:type, :string)
    field(:fee, :integer)
  end

  scalar :p2p_availabilities do
    serialize(fn p2p_availabilities ->
      p2p_availabilities
      |> Map.to_list()
      |> Enum.map(fn {
                       subset,
                       subset_map
                     } ->
        transform_subset_map_to_node_maps(subset_map, P2PSampling.list_nodes_to_sample(subset))
      end)
      |> List.flatten()
    end)
  end

  defp transform_subset_map_to_node_maps(
         %{
           end_of_node_synchronizations: end_of_node_synchronizations,
           node_average_availabilities: node_average_availabilities,
           node_availabilities: node_availabilities
         },
         list_nodes
       ) do
    transformed_node_availabilities =
      node_availabilities
      |> transform_node_availabilities()

    node_average_availabilities
    |> Enum.with_index()
    |> Enum.map(fn {node_average_availability, index} ->
      end_of_node_synchronization =
        end_of_node_synchronizations
        |> Enum.at(index, false)
        |> transform_end_of_node_synchronization()

      available =
        transformed_node_availabilities
        |> Enum.at(index)

      public_key =
        list_nodes
        |> Enum.at(index)
        |> Map.get(:last_public_key)
        |> Base.encode16()

      %{
        averageAvailability: node_average_availability,
        endOfNodeSynchronization: end_of_node_synchronization,
        available: available,
        publicKey: public_key
      }
    end)
  end

  defp transform_end_of_node_synchronization(false), do: false
  defp transform_end_of_node_synchronization(_), do: true

  defp transform_node_availabilities(bitstring, acc \\ [])

  defp transform_node_availabilities(<<1::size(1), rest::bitstring>>, acc),
    do: transform_node_availabilities(<<rest::bitstring>>, [true | acc])

  defp transform_node_availabilities(<<0::size(1), rest::bitstring>>, acc),
    do: transform_node_availabilities(<<rest::bitstring>>, [false | acc])

  defp transform_node_availabilities(<<>>, acc), do: acc
end
