defmodule Uniris.BeaconChain.Slot do
  @moduledoc """
  Represent a beacon chain slot generated after each synchronization interval
  with the transaction stored and nodes updates
  """
  alias __MODULE__.EndOfNodeSync
  alias __MODULE__.TransactionSummary

  alias Uniris.Crypto

  alias Uniris.Utils

  @genesis_previous_hash Enum.map(1..33, fn _ -> <<0>> end) |> :erlang.list_to_binary()

  defstruct [
    :subset,
    :slot_time,
    previous_hash: @genesis_previous_hash,
    transaction_summaries: [],
    end_of_node_synchronizations: [],
    p2p_view: <<>>,
    involved_nodes: <<>>,
    validation_signatures: %{}
  ]

  @type t :: %__MODULE__{
          subset: binary(),
          slot_time: DateTime.t(),
          previous_hash: binary(),
          transaction_summaries: list(TransactionSummary.t()),
          end_of_node_synchronizations: list(EndOfNodeSync.t()),
          p2p_view: bitstring(),
          involved_nodes: bitstring(),
          validation_signatures: %{(node_position :: non_neg_integer()) => binary()}
        }

  @doc """
  Return the genesis previous hash
  """
  @spec genesis_previous_hash() :: binary()
  def genesis_previous_hash, do: @genesis_previous_hash

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
  Provide a digest for a beacon slot

  ## Examples

    iex> %Slot{
    ...>   subset: <<0>>,
    ...>   slot_time: ~U[2021-01-20 10:10:00Z],
    ...>   previous_hash: <<0, 181, 97, 209, 67, 114, 34, 235, 88, 254, 95, 18, 156, 110, 124, 203, 4,
    ...>     112, 176, 181, 102, 86, 173, 170, 23, 109, 146, 180, 153, 104, 28, 110, 146>>,
    ...>   transaction_summaries: [
    ...>     %TransactionSummary{
    ...>        address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
    ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
    ...>        timestamp: ~U[2020-06-25 15:11:53Z],
    ...>        type: :transfer,
    ...>        movements_addresses: []
    ...>     }
    ...>   ],
    ...>   end_of_node_synchronizations: [ %EndOfNodeSync{
    ...>     public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
    ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
    ...>     timestamp: ~U[2020-06-25 15:11:53Z]
    ...>   }],
    ...>   p2p_view: <<0::1, 1::1, 1::1, 1::1, 1::1>>
    ...> }
    ...> |> Slot.digest()
    <<0, 50, 64, 179, 89, 145, 90, 41, 206, 29, 239, 141, 232, 172, 65,
    160, 17, 213, 9, 152, 63, 34, 4, 137, 124, 78, 17, 123, 149, 133, 246, 243, 136>>
  """
  @spec digest(t()) :: binary()
  def digest(slot = %__MODULE__{}) do
    slot
    |> serialize_before_validation()
    |> Crypto.hash()
  end

  defp serialize_before_validation(%__MODULE__{
         subset: subset,
         slot_time: slot_time,
         previous_hash: previous_hash,
         transaction_summaries: transaction_summaries,
         end_of_node_synchronizations: end_of_node_synchronizations,
         p2p_view: p2p_view
       }) do
    transaction_summaries_bin =
      transaction_summaries
      |> Enum.map(&TransactionSummary.serialize/1)
      |> :erlang.list_to_binary()

    end_of_node_synchronizations_bin =
      end_of_node_synchronizations
      |> Enum.map(&EndOfNodeSync.serialize/1)
      |> :erlang.list_to_binary()

    <<subset::binary, DateTime.to_unix(slot_time)::32, previous_hash::binary,
      length(transaction_summaries)::32, transaction_summaries_bin::binary,
      length(end_of_node_synchronizations)::16, end_of_node_synchronizations_bin::binary,
      bit_size(p2p_view)::16, p2p_view::bitstring>>
  end

  @doc """
  Serialize a BeaconSlot into a binary format

    ## Examples

        iex> %Slot{
        ...>    subset: <<0>>,
        ...>    slot_time: ~U[2021-01-20 10:10:00Z],
        ...>    previous_hash: <<0, 181, 97, 209, 67, 114, 34, 235, 88, 254, 95, 18, 156, 110, 124, 203, 4,
        ...>      112, 176, 181, 102, 86, 173, 170, 23, 109, 146, 180, 153, 104, 28, 110, 146>>,
        ...>    transaction_summaries: [
        ...>      %TransactionSummary{
        ...>        address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
        ...>        timestamp: ~U[2020-06-25 15:11:53Z],
        ...>        type: :transfer,
        ...>        movements_addresses: []
        ...>      }
        ...>    ],
        ...>    end_of_node_synchronizations: [ %EndOfNodeSync{
        ...>      public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
        ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
        ...>      timestamp: ~U[2020-06-25 15:11:53Z]
        ...>    }],
        ...>    p2p_view: <<1::1, 0::1, 1::1, 1::1>>,
        ...>    involved_nodes: <<0::1, 1::1, 0::1, 0::1>>,
        ...>    validation_signatures: %{ 1 => <<194, 20, 133, 185, 6, 130, 218, 157, 233, 83, 166, 166, 66, 90, 63, 142, 147,
        ...>      201, 236, 62, 113, 45, 223, 78, 98, 138, 168, 152, 170, 137, 128, 47, 171,
        ...>      181, 214, 43, 149, 88, 183, 9, 170, 55, 134, 25, 46, 24, 243, 146, 82, 165,
        ...>      73, 196, 182, 182, 220, 10, 181, 137, 113, 78, 34, 100, 194, 88>> }
        ...>  } |> Slot.serialize()
        <<
        # Subset
        0,
        # Slot time
        96, 8, 1, 120,
        # Previous hash
        0, 181, 97, 209, 67, 114, 34, 235, 88, 254, 95, 18, 156, 110, 124, 203, 4,
        112, 176, 181, 102, 86, 173, 170, 23, 109, 146, 180, 153, 104, 28, 110, 146,
        # Nb transaction summaries
        0, 0, 0, 1,
        # Address
        0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
        # Timestamp
        94, 244, 190, 185,
        # Type
        2,
        # Nb movements addresses
        0, 0,
        # Nb of node synchronizations
        0, 1,
        # Node public key
        0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
        100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
        # Node readyness timestamp
        94, 244, 190, 185,
        # P2P view bitstring size
        0, 4,
        # P2P view bitstring
        1::1, 0::1, 1::1, 1::1,
        # Size involved nodes bitstring
        4,
        # Involved nodes bitstring
        0::1, 1::1, 0::1, 0::1,
        # Validation signature node's position
        1,
        # Validation signature size
        64,
        # Validation signature for the involved node at position 0
        194, 20, 133, 185, 6, 130, 218, 157, 233, 83, 166, 166, 66, 90, 63, 142, 147,
        201, 236, 62, 113, 45, 223, 78, 98, 138, 168, 152, 170, 137, 128, 47, 171,
        181, 214, 43, 149, 88, 183, 9, 170, 55, 134, 25, 46, 24, 243, 146, 82, 165,
        73, 196, 182, 182, 220, 10, 181, 137, 113, 78, 34, 100, 194, 88
        >>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(
        slot = %__MODULE__{
          involved_nodes: involved_nodes,
          validation_signatures: validation_signatures
        }
      ) do
    validation_signatures_bin =
      validation_signatures
      |> Enum.map(fn {pos, sig} -> <<pos::8, byte_size(sig)::8, sig::binary>> end)
      |> :erlang.list_to_binary()

    <<serialize_before_validation(slot)::bitstring, bit_size(involved_nodes)::8,
      involved_nodes::bitstring, validation_signatures_bin::binary>>
  end

  @doc """
  Deserialize an encoded BeaconSlot

  ## Examples

      iex> <<0, 96, 8, 1, 120, 0, 181, 97, 209, 67, 114, 34, 235, 88, 254, 95, 18, 156, 110, 124, 203, 4,
      ...>   112, 176, 181, 102, 86, 173, 170, 23, 109, 146, 180, 153, 104, 28, 110, 146, 0, 0, 0, 1,
      ...>   0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>   99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...>   94, 244, 190, 185, 2, 0, 0, 0, 1,
      ...>   0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>   100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
      ...>   94, 244, 190, 185, 0, 4, 1::1, 0::1, 1::1, 1::1,
      ...>   4, 0::1, 1::1, 0::1, 0::1, 1,
      ...>   64, 194, 20, 133, 185, 6, 130, 218, 157, 233, 83, 166, 166, 66, 90, 63, 142, 147,
      ...>   201, 236, 62, 113, 45, 223, 78, 98, 138, 168, 152, 170, 137, 128, 47, 171,
      ...>   181, 214, 43, 149, 88, 183, 9, 170, 55, 134, 25, 46, 24, 243, 146, 82, 165,
      ...>   73, 196, 182, 182, 220, 10, 181, 137, 113, 78, 34, 100, 194, 88
      ...> >>
      ...> |> Slot.deserialize()
      {
        %Slot{
          subset: <<0>>,
          slot_time: ~U[2021-01-20 10:10:00Z],
          previous_hash: <<0, 181, 97, 209, 67, 114, 34, 235, 88, 254, 95, 18, 156, 110, 124, 203, 4,
            112, 176, 181, 102, 86, 173, 170, 23, 109, 146, 180, 153, 104, 28, 110, 146>>,
          transaction_summaries: [
            %TransactionSummary{
              address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
              timestamp: ~U[2020-06-25 15:11:53Z],
              type: :transfer,
              movements_addresses: []
            }
          ],
          end_of_node_synchronizations: [ %EndOfNodeSync{
            public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
            100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
            timestamp: ~U[2020-06-25 15:11:53Z]
          }],
          p2p_view: <<1::1, 0::1, 1::1, 1::1>>,
          involved_nodes: <<0::1, 1::1, 0::1, 0::1>>,
          validation_signatures: %{ 1 => <<194, 20, 133, 185, 6, 130, 218, 157, 233, 83, 166, 166, 66, 90, 63, 142, 147,
            201, 236, 62, 113, 45, 223, 78, 98, 138, 168, 152, 170, 137, 128, 47, 171,
            181, 214, 43, 149, 88, 183, 9, 170, 55, 134, 25, 46, 24, 243, 146, 82, 165,
            73, 196, 182, 182, 220, 10, 181, 137, 113, 78, 34, 100, 194, 88>>}
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<subset::8, slot_timestamp::32, rest::bitstring>>) do
    {previous_hash, <<nb_transaction_summaries::32, rest::bitstring>>} = deserialize_hash(rest)
    {tx_summaries, rest} = deserialize_tx_summaries(rest, nb_transaction_summaries, [])
    <<nb_end_of_sync::16, rest::bitstring>> = rest

    {end_of_node_synchronizations, rest} =
      deserialize_end_of_node_synchronizations(rest, nb_end_of_sync, [])

    <<p2p_view_size::16, p2p_view::bitstring-size(p2p_view_size), rest::bitstring>> = rest

    <<involved_nodes_size::8, involved_nodes::bitstring-size(involved_nodes_size),
      rest::bitstring>> = rest

    nb_involved_nodes = Utils.count_bitstring_bits(involved_nodes)

    {validation_signatures, rest} =
      deserialize_validation_signatures(rest, nb_involved_nodes, %{})

    {
      %__MODULE__{
        subset: <<subset>>,
        slot_time: DateTime.from_unix!(slot_timestamp),
        previous_hash: previous_hash,
        transaction_summaries: tx_summaries,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: p2p_view,
        involved_nodes: involved_nodes,
        validation_signatures: validation_signatures
      },
      rest
    }
  end

  defp deserialize_hash(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<hash::binary-size(hash_size), rest::bitstring>> = rest
    {<<hash_id::8, hash::binary>>, rest}
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

  defp deserialize_validation_signatures(rest, 0, _acc), do: {%{}, rest}

  defp deserialize_validation_signatures(rest, nb_involved_nodes, acc)
       when map_size(acc) == nb_involved_nodes do
    {acc, rest}
  end

  defp deserialize_validation_signatures(
         <<pos::8, signature_size::8, signature::binary-size(signature_size), rest::bitstring>>,
         nb_involved_nodes,
         acc
       ) do
    deserialize_validation_signatures(rest, nb_involved_nodes, Map.put(acc, pos, signature))
  end

  @doc """
  Determines if the beacon slot contains a given transaction

  ## Examples

      iex> %Slot{
      ...>   transaction_summaries: []
      ...> }
      ...> |> Slot.has_transaction?(<<0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...> 221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>)
      false

      iex> %Slot{
      ...>   transaction_summaries: [%TransactionSummary{
      ...>      address: <<0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...>               221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>,
      ...>      timestamp: ~U[2020-06-25 15:11:53Z],
      ...>      type: :transfer,
      ...>      movements_addresses: []
      ...>   }]
      ...> }
      ...> |> Slot.has_transaction?(<<0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...> 221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>)
      true
  """
  @spec has_transaction?(__MODULE__.t(), binary()) :: boolean()
  def has_transaction?(%__MODULE__{transaction_summaries: transaction_summaries}, address) do
    Enum.any?(transaction_summaries, &(&1.address == address))
  end

  @spec has_changes?(t()) :: boolean
  def has_changes?(%__MODULE__{
        transaction_summaries: transaction_summaries,
        end_of_node_synchronizations: end_of_node_sync
      })
      when length(transaction_summaries) > 0 or length(end_of_node_sync) > 0 do
    true
  end

  def has_changes?(%__MODULE__{}), do: false
end
