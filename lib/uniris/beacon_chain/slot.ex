defmodule Uniris.BeaconChain.Slot do
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

  @doc """
  Add a transaction info to the list of transactions if not exists

  ## Examples

      iex> %Slot{}
      ...> |> Slot.add_transaction_info(%TransactionInfo{
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
        transactions: [
          %TransactionInfo{
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
  @spec add_transaction_info(__MODULE__.t(), TransactionInfo.t()) :: __MODULE__.t()
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

  @doc """
  Add a node info to the list of nodes

  ## Examples

      iex> %Slot{}
      ...> |> Slot.add_node_info(%NodeInfo{
      ...>   public_key:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z]
      ...> })
      %Slot{
        nodes: [
          %NodeInfo{
            public_key:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
               168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
            timestamp: ~U[2020-06-25 15:11:53Z],
          }
        ]
      }
  """
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

      iex> %Slot{
      ...>   transactions: [
      ...>     %TransactionInfo{
      ...>        address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>          99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
      ...>        timestamp: ~U[2020-06-25 15:11:53Z],
      ...>        type: :transfer,
      ...>        movements_addresses: []
      ...>     }
      ...>   ],
      ...>   nodes: [ %NodeInfo{
      ...>     public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>      100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
      ...>     timestamp: ~U[2020-06-25 15:11:53Z],
      ...>     ready?: true
      ...>   }]
      ...> }
      ...> |> Slot.serialize()
      <<
      # Nb transactions info
      0, 0, 0, 1,
      # Transaction address
      0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      # Timestamp
      94, 244, 190, 185,
      # Type
      2,
      # Nb movement addresses
      0, 0,
      # Nb nodes info
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
        transactions: transactions_info,
        nodes: nodes_info
      }) do
    transactions_info_bin =
      transactions_info
      |> Enum.map(&TransactionInfo.serialize/1)
      |> :erlang.list_to_binary()

    nodes_info_bin =
      nodes_info
      |> Enum.map(&NodeInfo.serialize/1)
      |> :erlang.list_to_bitstring()

    <<length(transactions_info)::32, transactions_info_bin::binary, length(nodes_info)::16,
      nodes_info_bin::bitstring>>
  end

  @doc """
  Deserialize an encoded BeaconSlot

  ## Examples

      iex> <<0, 0, 0, 1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...> 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...> 94, 244, 190, 185, 2, 0, 0, 0, 1,
      ...> 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...> 100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
      ...> 94, 244, 190, 185, 1::1>>
      ...> |> Slot.deserialize()
      {
        %Slot{
          transactions: [
            %TransactionInfo{
              address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
              timestamp: ~U[2020-06-25 15:11:53Z],
              type: :transfer,
              movements_addresses: []
            }
          ],
          nodes: [ %NodeInfo{
            public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
            100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
            timestamp: ~U[2020-06-25 15:11:53Z],
            ready?: true
          }]
        },
        ""
      }
  """
  def deserialize(<<nb_transactions_info::32, rest::bitstring>>) do
    {txs_info, rest} = deserialize_tx_info(rest, nb_transactions_info, [])
    <<nb_nodes_info::16, rest::bitstring>> = rest
    {nodes_info, rest} = deserialize_node_info(rest, nb_nodes_info, [])

    {
      %__MODULE__{
        transactions: txs_info,
        nodes: nodes_info
      },
      rest
    }
  end

  defp deserialize_tx_info(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_info(rest, nb_txs_info, acc) when length(acc) == nb_txs_info do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_info(rest, nb_txs_info, acc) do
    {tx_info, rest} = TransactionInfo.deserialize(rest)
    deserialize_tx_info(rest, nb_txs_info, [tx_info | acc])
  end

  defp deserialize_node_info(rest, 0, _acc), do: {[], rest}

  defp deserialize_node_info(rest, nb_nodes_info, acc) when length(acc) == nb_nodes_info do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_node_info(rest, nb_nodes_info, acc) do
    {node_info, rest} = NodeInfo.deserialize(rest)
    deserialize_tx_info(rest, nb_nodes_info, [node_info | acc])
  end

  @doc """
  Determines if the beacon slot contains a given transaction

  ## Examples

      iex> %Slot{
      ...>   transactions: []
      ...> }
      ...> |> Slot.has_transaction?(<<0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...> 221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>)
      false

      iex> %Slot{
      ...>   transactions: [%TransactionInfo{
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
  def has_transaction?(%__MODULE__{transactions: transactions}, address) do
    Enum.any?(transactions, &(&1.address == address))
  end
end
