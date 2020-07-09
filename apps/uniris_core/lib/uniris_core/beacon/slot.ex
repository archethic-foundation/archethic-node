defmodule UnirisCore.BeaconSlot do
  @moduledoc """
  Represent a beacon chain slot generated after each synchronization interval
  with the transaction stored and nodes updates
  """
  alias __MODULE__.NodeInfo
  alias __MODULE__.TransactionInfo

  defstruct transactions: [], nodes: []

  @type t :: %__MODULE__{
          transactions: list(TransactionInfo.t()),
          nodes: list(NodeInfo.t())
        }

  def add_transaction_info(
        slot = %__MODULE__{transactions: transactions},
        info = %TransactionInfo{address: tx_address}
      ) do
    if Enum.any?(transactions, &(&1.address == tx_address)) do
      slot
    else
      Map.update!(
        slot,
        :transactions,
        &(&1 ++ [info])
      )
    end
  end

  def add_node_info(slot = %__MODULE__{}, info = %NodeInfo{}) do
    Map.update!(
      slot,
      :nodes,
      &(&1 ++ [info])
    )
  end

  @doc """
  Serialize a beacon slot into binary format

  ## Examples

      iex> %UnirisCore.BeaconSlot{
      ...>   transactions: [
      ...>     %UnirisCore.BeaconSlot.TransactionInfo{
      ...>        address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>        timestamp: ~U[2020-06-25 15:11:53Z],
      ...>        type: :transfer,
      ...>        movements_addresses: []
      ...>     }
      ...>   ],
      ...>   nodes: [ %UnirisCore.BeaconSlot.NodeInfo{
      ...>     public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
      ...>     timestamp: ~U[2020-06-25 15:11:53Z],
      ...>     ready?: true
      ...>   }]
      ...> }
      ...> |> UnirisCore.BeaconSlot.serialize()
      <<
      # Nb transaction infos
      0, 0, 0, 1,
      # Transaction adddress
      0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      # Timestamp
      94, 244, 190, 185,
      # Type
      2,
      # Nb movement addresses
      0, 0,
      # Nb node infos
      0, 1,
      # Public key
      0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
      # Timestamp
      94, 244, 190, 185,
      # Ready
      1::1
      >>
  """
  def serialize(%__MODULE__{
        transactions: transaction_infos,
        nodes: node_infos
      }) do
    transaction_infos_bin =
      transaction_infos
      |> Enum.map(&TransactionInfo.serialize/1)
      |> :erlang.list_to_binary()

    node_infos_bin =
      node_infos
      |> Enum.map(&NodeInfo.serialize/1)
      |> :erlang.list_to_bitstring()

    <<length(transaction_infos)::32, transaction_infos_bin::binary, length(node_infos)::16,
      node_infos_bin::bitstring>>
  end

  @doc """
  Deserialize an encoded BeaconSlot

  ## Examples

      iex> %UnirisCore.BeaconSlot{
      ...>   transactions: [
      ...>     %UnirisCore.BeaconSlot.TransactionInfo{
      ...>        address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>        timestamp: ~U[2020-06-25 15:11:53Z],
      ...>        type: :transfer,
      ...>        movements_addresses: []
      ...>     }
      ...>   ],
      ...>   nodes: [ %UnirisCore.BeaconSlot.NodeInfo{
      ...>     public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
      ...>     timestamp: ~U[2020-06-25 15:11:53Z],
      ...>     ready?: true
      ...>   }]
      ...> }
      ...> |> UnirisCore.BeaconSlot.serialize()
      ...> |> UnirisCore.BeaconSlot.deserialize()
      {
        %UnirisCore.BeaconSlot{
          transactions: [
            %UnirisCore.BeaconSlot.TransactionInfo{
              address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
              timestamp: ~U[2020-06-25 15:11:53Z],
              type: :transfer,
              movements_addresses: []
            }
          ],
          nodes: [ %UnirisCore.BeaconSlot.NodeInfo{
            public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
            100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
            timestamp: ~U[2020-06-25 15:11:53Z],
            ready?: true
          }]
        },
        ""
      }
  """
  def deserialize(<<nb_transaction_infos::32, rest::bitstring>>) do
    {tx_infos, rest} = deserialize_tx_info(rest, nb_transaction_infos, [])
    <<nb_node_infos::16, rest::bitstring>> = rest
    {node_infos, rest} = deserialize_node_info(rest, nb_node_infos, [])

    {
      %__MODULE__{
        transactions: tx_infos,
        nodes: node_infos
      },
      rest
    }
  end

  defp deserialize_tx_info(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_info(rest, nb_tx_infos, acc) when length(acc) == nb_tx_infos do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_info(rest, nb_tx_infos, acc) do
    {tx_info, rest} = TransactionInfo.deserialize(rest)
    deserialize_tx_info(rest, nb_tx_infos, [tx_info | acc])
  end

  defp deserialize_node_info(rest, 0, _acc), do: {[], rest}

  defp deserialize_node_info(rest, nb_node_infos, acc) when length(acc) == nb_node_infos do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_node_info(rest, nb_node_infos, acc) do
    {node_info, rest} = NodeInfo.deserialize(rest)
    deserialize_tx_info(rest, nb_node_infos, [node_info | acc])
  end
end
