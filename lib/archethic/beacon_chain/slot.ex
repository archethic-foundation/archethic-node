defmodule ArchEthic.BeaconChain.Slot do
  @moduledoc """
  Represent a beacon chain slot generated after each synchronization interval
  with the transaction stored and nodes updates
  """
  alias __MODULE__.EndOfNodeSync
  alias __MODULE__.TransactionSummary

  alias ArchEthic.BeaconChain.Subset.P2PSampling

  alias ArchEthic.BeaconChain.SummaryTimer

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  @type net_stats :: list(%{latency: non_neg_integer()})

  defstruct [
    :subset,
    :slot_time,
    transaction_summaries: [],
    end_of_node_synchronizations: [],
    p2p_view: %{
      availabilities: <<>>,
      network_stats: []
    },
    involved_nodes: <<>>
  ]

  @type t :: %__MODULE__{
          subset: binary(),
          slot_time: DateTime.t(),
          transaction_summaries: list(TransactionSummary.t()),
          end_of_node_synchronizations: list(EndOfNodeSync.t()),
          p2p_view: %{
            availabilities: bitstring(),
            network_stats: net_stats()
          },
          involved_nodes: bitstring()
        }

  @doc """
  Add a transaction summary to the slot if not exists

  ## Examples

      iex> %Slot{}
      ...> |> Slot.add_transaction_summary(%TransactionSummary{
      ...>   address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z],
      ...>   type: :transfer,
      ...>   movements_addresses: [
      ...>       <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>       99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      ...>   ]
      ...> })
      %Slot{
        transaction_summaries: [
          %TransactionSummary{
            address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
               168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
            timestamp: ~U[2020-06-25 15:11:53Z],
            type: :transfer,
            movements_addresses: [
                <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
            ]
          }
        ]
      }
  """
  @spec add_transaction_summary(__MODULE__.t(), TransactionSummary.t()) :: __MODULE__.t()
  def add_transaction_summary(
        slot = %__MODULE__{transaction_summaries: transaction_summaries},
        info = %TransactionSummary{address: tx_address}
      ) do
    if Enum.any?(transaction_summaries, &(&1.address == tx_address)) do
      slot
    else
      Map.update!(
        slot,
        :transaction_summaries,
        &(&1 ++ [info])
      )
    end
  end

  @doc """
  Add an end of node synchronization to the slot

  ## Examples

      iex> %Slot{}
      ...> |> Slot.add_end_of_node_sync(%EndOfNodeSync{
      ...>   public_key:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z]
      ...> })
      %Slot{
        end_of_node_synchronizations: [
          %EndOfNodeSync{
            public_key:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
               168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
            timestamp: ~U[2020-06-25 15:11:53Z]
          }
        ]
      }
  """
  def add_end_of_node_sync(slot = %__MODULE__{}, end_of_sync = %EndOfNodeSync{}) do
    Map.update!(
      slot,
      :end_of_node_synchronizations,
      &(&1 ++ [end_of_sync])
    )
  end

  @doc """
  Add the p2p views to the beacon slot

  ## Examples

      iex> %Slot{
      ...>    p2p_view: %{ availabilities: <<0::1, 0::1, 0::1>>, network_stats: [] }
      ...>  }
      ...> |> Slot.add_p2p_view([{true, 10 }, {false, 0 }, {true, 50 }])
      %Slot{
        p2p_view: %{
          availabilities: <<1::1, 0::1, 1::1>>,
          network_stats: [
            %{ latency: 10 },
            %{ latency: 0},
            %{ latency: 50}
          ]
        }
      }
  """
  @spec add_p2p_view(t(), list(P2PSampling.p2p_view())) :: t()
  def add_p2p_view(slot = %__MODULE__{}, p2p_views) do
    %{availabilities: availabilities, network_stats: network_stats} =
      p2p_views
      |> Enum.reduce(%{availabilities: [], network_stats: []}, fn
        {true, latency}, acc ->
          acc
          |> Map.update!(:availabilities, &(&1 ++ [<<1::1>>]))
          |> Map.update!(:network_stats, &(&1 ++ [%{latency: latency}]))

        {false, _}, acc ->
          acc
          |> Map.update!(:availabilities, &(&1 ++ [<<0::1>>]))
          |> Map.update!(:network_stats, &(&1 ++ [%{latency: 0}]))
      end)

    %{
      slot
      | p2p_view: %{
          availabilities: :erlang.list_to_bitstring(availabilities),
          network_stats: network_stats
        }
    }
  end

  @doc """
  Serialize a BeaconSlot into a binary format

    ## Examples

        iex> %Slot{
        ...>    subset: <<0>>,
        ...>    slot_time: ~U[2021-01-20 10:10:00Z],
        ...>    transaction_summaries: [
        ...>      %TransactionSummary{
        ...>        address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
        ...>        timestamp: ~U[2020-06-25 15:11:53Z],
        ...>        type: :transfer,
        ...>        movements_addresses: []
        ...>      }
        ...>    ],
        ...>    end_of_node_synchronizations: [ %EndOfNodeSync{
        ...>      public_key: <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
        ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
        ...>      timestamp: ~U[2020-06-25 15:11:53Z]
        ...>    }],
        ...>    p2p_view: %{
        ...>      availabilities: <<1::1, 0::1>>,
        ...>      network_stats: [
        ...>         %{ latency: 10},
        ...>         %{ latency: 0}
        ...>      ]
        ...>    },
        ...>    involved_nodes: <<0::1, 1::1, 0::1, 0::1>>
        ...>  } |> Slot.serialize()
        <<
        # Subset
        0,
        # Slot time
        96, 8, 1, 120,
        # Nb transaction summaries
        0, 0, 0, 1,
        # Address
        0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
        # Timestamp
        0, 0, 1, 114, 236, 9, 2, 168,
        # Type (transfer)
        253,
        # Nb movements addresses
        0, 0,
        # Nb of node synchronizations
        0, 1,
        # Node public key
        0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
        100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
        # Node readyness timestamp
        94, 244, 190, 185,
        # P2P view bitstring size
        0, 2,
        # P2P view availabilies
        1::1, 0::1,
        # P2P view network stats (1st node)
        10,
        # P2P view network stats (2nd node)
        0,
        # Size involved nodes bitstring
        4,
        # Involved nodes bitstring
        0::1, 1::1, 0::1, 0::1
        >>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        subset: subset,
        slot_time: slot_time,
        transaction_summaries: transaction_summaries,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: %{
          availabilities: availabilities,
          network_stats: network_stats
        },
        involved_nodes: involved_nodes
      }) do
    transaction_summaries_bin =
      transaction_summaries
      |> Enum.map(&TransactionSummary.serialize/1)
      |> :erlang.list_to_binary()

    end_of_node_synchronizations_bin =
      end_of_node_synchronizations
      |> Enum.map(&EndOfNodeSync.serialize/1)
      |> :erlang.list_to_binary()

    net_stats_bin =
      network_stats
      |> Enum.map(fn %{latency: latency} -> <<latency::8>> end)
      |> :erlang.list_to_binary()

    <<subset::binary, DateTime.to_unix(slot_time)::32, length(transaction_summaries)::32,
      transaction_summaries_bin::binary, length(end_of_node_synchronizations)::16,
      end_of_node_synchronizations_bin::binary, bit_size(availabilities)::16,
      availabilities::bitstring, net_stats_bin::binary, bit_size(involved_nodes)::8,
      involved_nodes::bitstring>>
  end

  @doc """
  Deserialize an encoded BeaconSlot

  ## Examples

      iex> <<0, 96, 8, 1, 120, 0, 0, 0, 1,
      ...>  0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>  99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...>  0, 0, 1, 114, 236, 9, 2, 168, 253, 0, 0,
      ...>  0, 1, 0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>  100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241, 94, 244, 190, 185,
      ...>  0, 2, 1::1, 0::1, 10,
      ...>  0, 4, 0::1, 1::1, 0::1, 0::1>>
      ...> |> Slot.deserialize()
      {
        %Slot{
          subset: <<0>>,
          slot_time: ~U[2021-01-20 10:10:00Z],
          transaction_summaries: [
            %TransactionSummary{
              address: <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
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
          }],
          p2p_view: %{
            availabilities: <<1::1, 0::1>>,
            network_stats: [
              %{ latency: 10},
              %{ latency: 0}
            ]
          },
          involved_nodes: <<0::1, 1::1, 0::1, 0::1>>
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(
        <<subset::8, slot_timestamp::32, nb_transaction_summaries::32, rest::bitstring>>
      ) do
    {tx_summaries, rest} = deserialize_tx_summaries(rest, nb_transaction_summaries, [])
    <<nb_end_of_sync::16, rest::bitstring>> = rest

    {end_of_node_synchronizations, rest} =
      deserialize_end_of_node_synchronizations(rest, nb_end_of_sync, [])

    <<p2p_view_size::16, availabilities::bitstring-size(p2p_view_size), rest::bitstring>> = rest

    {network_stats, rest} = deserialize_network_stats(rest, p2p_view_size, [])

    <<involved_nodes_size::8, involved_nodes::bitstring-size(involved_nodes_size),
      rest::bitstring>> = rest

    {
      %__MODULE__{
        subset: <<subset>>,
        slot_time: DateTime.from_unix!(slot_timestamp),
        transaction_summaries: tx_summaries,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: %{
          availabilities: availabilities,
          network_stats: network_stats
        },
        involved_nodes: involved_nodes
      },
      rest
    }
  end

  defp deserialize_tx_summaries(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_summaries(rest, nb_tx_summaries, acc) when length(acc) == nb_tx_summaries do
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
    {end_of_sync, rest} = EndOfNodeSync.deserialize(rest)

    deserialize_end_of_node_synchronizations(rest, nb_end_of_node_synchronizations, [
      end_of_sync | acc
    ])
  end

  defp deserialize_network_stats(rest, 0, _), do: {[], rest}

  defp deserialize_network_stats(rest, nb_nodes, acc) when nb_nodes == length(acc) do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_network_stats(<<latency::8, rest::bitstring>>, nb_nodes, acc) do
    deserialize_network_stats(rest, nb_nodes, [%{latency: latency} | acc])
  end

  @doc """
  Determines if the beacon slot contains a given transaction

  ## Examples

      iex> %Slot{
      ...>   transaction_summaries: []
      ...> }
      ...> |> Slot.has_transaction?(<<0, 0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...> 221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>)
      false

      iex> %Slot{
      ...>   transaction_summaries: [%TransactionSummary{
      ...>      address: <<0, 0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...>               221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>,
      ...>      timestamp: ~U[2020-06-25 15:11:53Z],
      ...>      type: :transfer,
      ...>      movements_addresses: []
      ...>   }]
      ...> }
      ...> |> Slot.has_transaction?(<<0, 0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...> 221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>)
      true
  """
  @spec has_transaction?(__MODULE__.t(), binary()) :: boolean()
  def has_transaction?(%__MODULE__{transaction_summaries: transaction_summaries}, address) do
    Enum.any?(transaction_summaries, &(&1.address == address))
  end

  @spec has_changes?(t()) :: boolean
  def has_changes?(%__MODULE__{
        transaction_summaries: [],
        end_of_node_synchronizations: [],
        p2p_view: %{
          availabilities: <<>>
        }
      }) do
    false
  end

  def has_changes?(%__MODULE__{}), do: true

  @doc """
  Retrieve the nodes responsible to manage the slot processing
  """
  @spec involved_nodes(t()) :: list(Node.t())
  def involved_nodes(%__MODULE__{subset: subset, slot_time: slot_time}) do
    node_list =
      Enum.filter(
        P2P.authorized_nodes(),
        &(DateTime.compare(&1.authorization_date, slot_time) == :lt)
      )

    Election.beacon_storage_nodes(
      subset,
      slot_time,
      node_list,
      Election.get_storage_constraints()
    )
  end

  @doc """
  Retrieve the nodes responsible to manage the summary holding of the given slot
  """
  @spec summary_storage_nodes(t()) :: list(Node.t())
  def summary_storage_nodes(%__MODULE__{subset: subset, slot_time: slot_time}) do
    node_list =
      Enum.filter(
        P2P.authorized_nodes(),
        &(DateTime.compare(&1.authorization_date, slot_time) == :lt)
      )

    Election.beacon_storage_nodes(
      subset,
      SummaryTimer.next_summary(slot_time),
      node_list,
      Election.get_storage_constraints()
    )
  end

  @doc """
  Determines if the Slot is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{
        transaction_summaries: [],
        end_of_node_synchronizations: [],
        p2p_view: %{availabilities: <<>>, network_stats: []}
      }),
      do: true

  def empty?(%__MODULE__{}), do: false
end
