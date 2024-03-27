defmodule Archethic.BeaconChain.Slot do
  @moduledoc """
  Represent a beacon chain slot generated after each synchronization interval
  with the transaction stored and nodes updates
  """
  alias Archethic.BeaconChain.ReplicationAttestation
  alias __MODULE__.EndOfNodeSync

  alias Archethic.BeaconChain.Subset.P2PSampling

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type net_stats :: list(%{latency: non_neg_integer()})

  defstruct [
    :subset,
    :slot_time,
    transaction_attestations: [],
    end_of_node_synchronizations: [],
    p2p_view: %{
      availabilities: <<>>,
      network_stats: []
    },
    version: 1
  ]

  @type t :: %__MODULE__{
          version: pos_integer(),
          subset: binary(),
          slot_time: DateTime.t(),
          transaction_attestations: list(ReplicationAttestation.t()),
          end_of_node_synchronizations: list(EndOfNodeSync.t()),
          p2p_view: %{
            availabilities: bitstring(),
            network_stats: net_stats()
          }
        }

  @doc """
  Add a transaction attestation confirmation to the slot

  If the the transaction summary doesn't exist it will be added to the list of summaries with the first confirmation.

  If the transaction summary already exists, it will append the confirmation node with the node public key and its signature.

  Return true if transaction summary is new, false if transaction summary is updated

  ## Examples

    Add the first confirmation

      iex> %Slot{}
      ...> |> Slot.add_transaction_attestation(%ReplicationAttestation{
      ...>   transaction_summary: %TransactionSummary{
      ...>     address:
      ...>       <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>         168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>     timestamp: ~U[2020-06-25 15:11:53Z],
      ...>     type: :transfer,
      ...>     movements_addresses: [
      ...>       <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232,
      ...>         166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      ...>     ],
      ...>     fee: 10_000_000
      ...>   },
      ...>   confirmations: [
      ...>     {0,
      ...>      <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76, 29,
      ...>        230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119, 32, 180,
      ...>        47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124, 158, 142, 23,
      ...>        151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>}
      ...>   ]
      ...> })
      {true,
       %Slot{
         transaction_attestations: [
           %ReplicationAttestation{
             transaction_summary: %TransactionSummary{
               address:
                 <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
                   168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
               timestamp: ~U[2020-06-25 15:11:53Z],
               type: :transfer,
               movements_addresses: [
                 <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232,
                   166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
               ],
               fee: 10_000_000
             },
             confirmations: [
               {
                 0,
                 <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
                   29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119, 32,
                   180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124, 158, 142,
                   23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
               }
             ]
           }
         ]
       }}

    Append confirmation

       iex> %Slot{
       ...>   transaction_attestations: [
       ...>     %ReplicationAttestation{
       ...>       transaction_summary: %TransactionSummary{
       ...>         address:
       ...>           <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154,
       ...>             199, 168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41,
       ...>             247>>,
       ...>         timestamp: ~U[2020-06-25 15:11:53Z],
       ...>         type: :transfer,
       ...>         movements_addresses: [
       ...>           <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65,
       ...>             232, 166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204,
       ...>             255, 12>>
       ...>         ],
       ...>         fee: 10_000_000
       ...>       },
       ...>       confirmations: [
       ...>         {0,
       ...>          <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62,
       ...>            76, 29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49,
       ...>            119, 32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211,
       ...>            124, 158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>}
       ...>       ]
       ...>     }
       ...>   ]
       ...> }
       ...> |> Slot.add_transaction_attestation(%ReplicationAttestation{
       ...>   transaction_summary: %TransactionSummary{
       ...>     address:
       ...>       <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
       ...>         168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
       ...>     timestamp: ~U[2020-06-25 15:11:53Z],
       ...>     type: :transfer,
       ...>     movements_addresses: [
       ...>       <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232,
       ...>         166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
       ...>     ],
       ...>     fee: 10_000_000
       ...>   },
       ...>   confirmations: [
       ...>     {1,
       ...>      <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169, 155,
       ...>        63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38, 239, 151,
       ...>        241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134, 141, 174,
       ...>        141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>}
       ...>   ]
       ...> })
       {false,
        %Slot{
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary: %TransactionSummary{
                address:
                  <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
                    168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
                timestamp: ~U[2020-06-25 15:11:53Z],
                type: :transfer,
                movements_addresses: [
                  <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232,
                    166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
                ],
                fee: 10_000_000
              },
              confirmations: [
                {
                  0,
                  <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
                    29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
                    32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124, 158,
                    142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
                },
                {
                  1,
                  <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169, 155,
                    63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38, 239, 151,
                    241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134, 141, 174,
                    141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>
                }
              ]
            }
          ]
        }}

    Append transaction attestations

       iex> %Slot{
       ...>   transaction_attestations: [
       ...>     %ReplicationAttestation{
       ...>       transaction_summary: %TransactionSummary{
       ...>         address:
       ...>           <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154,
       ...>             199, 168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41,
       ...>             247>>,
       ...>         timestamp: ~U[2020-06-25 15:11:53Z],
       ...>         type: :transfer,
       ...>         movements_addresses: [],
       ...>         fee: 10_000_000
       ...>       },
       ...>       confirmations: [
       ...>         {0,
       ...>          <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62,
       ...>            76, 29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49,
       ...>            119, 32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211,
       ...>            124, 158, 142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>}
       ...>       ]
       ...>     }
       ...>   ]
       ...> }
       ...> |> Slot.add_transaction_attestation(%ReplicationAttestation{
       ...>   transaction_summary: %TransactionSummary{
       ...>     address:
       ...>       <<0, 0, 63, 243, 35, 90, 94, 187, 142, 185, 202, 188, 247, 248, 215, 170, 18, 115,
       ...>         50, 235, 117, 27, 105, 90, 132, 206, 105, 234, 200, 227, 176, 210, 46, 69>>,
       ...>     timestamp: ~U[2020-06-25 15:11:53Z],
       ...>     type: :transfer,
       ...>     movements_addresses: [],
       ...>     fee: 10_000_000
       ...>   },
       ...>   confirmations: [
       ...>     {1,
       ...>      <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169, 155,
       ...>        63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38, 239, 151,
       ...>        241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134, 141, 174,
       ...>        141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>}
       ...>   ]
       ...> })
       {true,
        %Slot{
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary: %TransactionSummary{
                address:
                  <<0, 0, 63, 243, 35, 90, 94, 187, 142, 185, 202, 188, 247, 248, 215, 170, 18, 115,
                    50, 235, 117, 27, 105, 90, 132, 206, 105, 234, 200, 227, 176, 210, 46, 69>>,
                timestamp: ~U[2020-06-25 15:11:53Z],
                type: :transfer,
                movements_addresses: [],
                fee: 10_000_000
              },
              confirmations: [
                {1,
                 <<89, 98, 246, 6, 202, 116, 247, 88, 69, 148, 188, 173, 34, 0, 194, 108, 169, 155,
                   63, 197, 200, 6, 31, 148, 57, 152, 195, 154, 181, 14, 77, 9, 161, 38, 239, 151,
                   241, 35, 93, 254, 65, 201, 152, 57, 187, 225, 86, 235, 56, 206, 134, 141, 174,
                   141, 29, 28, 173, 17, 4, 78, 129, 33, 68, 4>>}
              ]
            },
            %ReplicationAttestation{
              transaction_summary: %TransactionSummary{
                address:
                  <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
                    168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
                timestamp: ~U[2020-06-25 15:11:53Z],
                type: :transfer,
                movements_addresses: [],
                fee: 10_000_000
              },
              confirmations: [
                {
                  0,
                  <<185, 37, 172, 79, 189, 197, 94, 202, 41, 160, 222, 127, 227, 180, 133, 62, 76,
                    29, 230, 10, 100, 79, 47, 49, 139, 117, 0, 64, 89, 229, 228, 214, 6, 49, 119,
                    32, 180, 47, 189, 143, 239, 156, 56, 234, 236, 128, 17, 79, 236, 211, 124, 158,
                    142, 23, 151, 43, 50, 153, 52, 195, 144, 226, 247, 65>>
                }
              ]
            }
          ]
        }}

  """
  @spec add_transaction_attestation(
          __MODULE__.t(),
          ReplicationAttestation.t()
        ) ::
          {boolean(), __MODULE__.t()}
  def add_transaction_attestation(
        slot = %__MODULE__{transaction_attestations: transaction_attestations},
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{address: tx_address},
          confirmations: confirmations
        }
      ) do
    case Enum.find_index(
           transaction_attestations,
           &(&1.transaction_summary.address == tx_address)
         ) do
      nil ->
        {true, Map.update!(slot, :transaction_attestations, &[attestation | &1])}

      index ->
        {false, add_transaction_attestation_confirmations(slot, index, confirmations)}
    end
  end

  defp add_transaction_attestation_confirmations(slot, index, confirmations) do
    updated_attestations =
      Map.get(slot, :transaction_attestations)
      |> List.update_at(index, fn attestation ->
        Map.update!(
          attestation,
          :confirmations,
          &((&1 ++ confirmations) |> Enum.uniq_by(fn {node_index, _signature} -> node_index end))
        )
      end)

    Map.put(slot, :transaction_attestations, updated_attestations)
  end

  @doc """
  Add an end of node synchronization to the slot

  ## Examples

      iex> %Slot{}
      ...> |> Slot.add_end_of_node_sync(%EndOfNodeSync{
      ...>   public_key:
      ...>     <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199, 168,
      ...>       212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z]
      ...> })
      %Slot{
        end_of_node_synchronizations: [
          %EndOfNodeSync{
            public_key:
              <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199, 168,
                212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
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
      ...>   p2p_view: %{availabilities: <<0::16, 0::16, 0::16>>, network_stats: []}
      ...> }
      ...> |> Slot.add_p2p_view([{600, 10}, {0, 0}, {356, 50}])
      %Slot{
        p2p_view: %{
          availabilities: <<600::16, 0::16, 356::16>>,
          network_stats: [
            %{latency: 10},
            %{latency: 0},
            %{latency: 50}
          ]
        }
      }
  """
  @spec add_p2p_view(t(), list(P2PSampling.p2p_view())) :: t()
  def add_p2p_view(slot = %__MODULE__{}, p2p_views) do
    %{availabilities: availabilities, network_stats: network_stats} =
      p2p_views
      |> Enum.reduce(%{availabilities: [], network_stats: []}, fn {availability, latency}, acc ->
        acc
        |> Map.update!(:availabilities, &(&1 ++ [<<availability::16>>]))
        |> Map.update!(:network_stats, &(&1 ++ [%{latency: latency}]))
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
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        version: 1,
        subset: subset,
        slot_time: slot_time,
        transaction_attestations: transaction_attestations,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: %{
          availabilities: availabilities,
          network_stats: network_stats
        }
      }) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_binary()

    end_of_node_synchronizations_bin =
      end_of_node_synchronizations
      |> Enum.map(&EndOfNodeSync.serialize/1)
      |> :erlang.list_to_binary()

    net_stats_bin =
      network_stats
      |> Enum.map(fn %{latency: latency} -> <<latency::8>> end)
      |> :erlang.list_to_binary()

    encoded_transaction_attestations_len = length(transaction_attestations) |> VarInt.from_value()

    encoded_end_of_node_synchronizations_len =
      length(end_of_node_synchronizations) |> VarInt.from_value()

    <<1::8, subset::binary, DateTime.to_unix(slot_time)::32,
      encoded_transaction_attestations_len::binary, transaction_attestations_bin::binary,
      encoded_end_of_node_synchronizations_len::binary, end_of_node_synchronizations_bin::binary,
      length(network_stats)::16, availabilities::bitstring, net_stats_bin::binary>>
  end

  @doc """
  Deserialize an encoded BeaconSlot
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<1::8, subset::8, slot_timestamp::32, rest::bitstring>>) do
    {nb_transaction_attestations, rest} = rest |> VarInt.get_value()

    {tx_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    {nb_end_of_sync, rest} = rest |> VarInt.get_value()

    {end_of_node_synchronizations, rest} =
      deserialize_end_of_node_synchronizations(rest, nb_end_of_sync, [])

    <<p2p_view_size::16, rest::bitstring>> = rest

    availabilities_size = p2p_view_size * 2

    <<availabilities::binary-size(availabilities_size), rest::bitstring>> = rest

    {network_stats, rest} = deserialize_network_stats(rest, p2p_view_size, [])

    {
      %__MODULE__{
        version: 1,
        subset: <<subset>>,
        slot_time: DateTime.from_unix!(slot_timestamp),
        transaction_attestations: tx_attestations,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: %{
          availabilities: availabilities,
          network_stats: network_stats
        }
      },
      rest
    }
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
  Retrieve the nodes responsible to manage the slot processing
  """
  @spec involved_nodes(t()) :: list(Node.t())
  def involved_nodes(%__MODULE__{subset: subset, slot_time: slot_time}) do
    node_list = P2P.authorized_and_available_nodes(slot_time, true)

    Election.beacon_storage_nodes(
      subset,
      slot_time,
      node_list,
      Election.get_storage_constraints()
    )
  end

  @doc """
  Determines if the Slot is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{
        transaction_attestations: [],
        end_of_node_synchronizations: [],
        p2p_view: %{availabilities: <<>>, network_stats: []}
      }),
      do: true

  def empty?(%__MODULE__{}), do: false
end
