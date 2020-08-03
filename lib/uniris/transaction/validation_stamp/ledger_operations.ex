defmodule Uniris.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Set of the ledger operations taken by the network (transaction movements, node rewards, unspent outputs, fee)
  defined during the transaction mining
  """

  defstruct transaction_movements: [],
            node_movements: [],
            unspent_outputs: [],
            fee: 0.0

  alias Uniris.Crypto
  alias Uniris.Election

  alias Uniris.Mining.Fee

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Uniris.TransactionData
  alias Uniris.TransactionData.Ledger
  alias Uniris.TransactionData.Ledger.Transfer
  alias Uniris.TransactionData.UCOLedger

  @type t() :: %__MODULE__{
          transaction_movements: list(TransactionMovement.t()),
          node_movements: list(NodeMovement.t()),
          unspent_outputs: list(UnspentOutput.t()),
          fee: float()
        }

  @doc """
  Create a new ledger operations based on the pending transaction, unspent output transactions on the chain,
  node rewards and transaction fee

  Raise an error if the funds (unspent outputs) are unsufficients for the transfers or fee
  """
  @spec new!(
          transaction :: Transaction.pending(),
          fee :: float(),
          unspent_outputs :: list(UnspentOutput.t()),
          node_movements :: list(Movement.t())
        ) :: __MODULE__.t()
  def new!(tx = %Transaction{}, fee, unspent_outputs, node_movements)
      when is_float(fee) and is_list(unspent_outputs) and is_list(node_movements) do
    case transaction_movements(tx, unspent_outputs, fee) do
      {:ok, ops} ->
        %{ops | node_movements: node_movements}

      {:error, :unsufficient_funds} ->
        raise "Unsufficient funds for #{Base.encode16(tx.address)}"
    end
  end

  # Deduct the movements to applied for the transaction regarding the transfers and the unspent output transactions
  @spec transaction_movements(
          tx :: Transaction.pending(),
          utxo :: list(UnspentOutput.t()),
          fee :: float()
        ) :: {:ok, __MODULE__.t()} | {:error, :unsufficient_funds}
  defp transaction_movements(
         %Transaction{
           address: tx_address,
           data: %TransactionData{ledger: %Ledger{uco: %UCOLedger{transfers: []}}}
         },
         unspent_outputs,
         fee
       ) do
    sorted_utxos = Enum.sort_by(unspent_outputs, & &1.amount)
    uco_received = Enum.reduce(unspent_outputs, 0.0, &(&2 + &1.amount))

    if uco_received >= fee do
      {:ok, consume_utxos(%__MODULE__{fee: fee}, tx_address, sorted_utxos, fee)}
    else
      {:error, :unsufficient_funds}
    end
  end

  defp transaction_movements(
         %Transaction{
           address: tx_address,
           data: %TransactionData{ledger: %Ledger{uco: %UCOLedger{transfers: transfers}}}
         },
         unspent_outputs,
         fee
       ) do
    uco_to_spend =
      Enum.reduce(transfers, 0.0, fn %Transfer{amount: amount}, acc -> acc + amount end)

    sorted_utxos = Enum.sort_by(unspent_outputs, & &1.amount)
    uco_received = Enum.reduce(unspent_outputs, 0.0, &(&2 + &1.amount))

    if uco_received < uco_to_spend + fee do
      {:error, :unsufficient_funds}
    else
      transfers_movements =
        Enum.map(transfers, fn %Transfer{to: to, amount: amount} ->
          %TransactionMovement{to: to, amount: amount}
        end)

      ops = %__MODULE__{fee: fee, transaction_movements: transfers_movements}

      {:ok, consume_utxos(ops, tx_address, sorted_utxos, uco_to_spend + fee)}
    end
  end

  defp consume_utxos(ops = %__MODULE__{}, tx_address, utxos, uco_amount) do
    new_utxos = do_consume_utxos(tx_address, utxos, uco_amount, 0.0)
    Map.put(ops, :unspent_outputs, new_utxos)
  end

  defp do_consume_utxos(tx_address, utxos, remaining, change)
       when remaining == 0.0 and change > 0.0 do
    [%UnspentOutput{amount: change, from: tx_address} | utxos]
  end

  defp do_consume_utxos(_tx_address, utxos, remaining, _change) when remaining == 0.0, do: utxos

  # When a full utxo is sufficient for the entire amount to spend
  # The uxto is fully consumed and remaining part is return as changed
  defp do_consume_utxos(tx_address, [%UnspentOutput{amount: amount} | rest], remaining, change)
       when amount >= remaining do
    do_consume_utxos(tx_address, rest, 0.0, change + (amount - remaining))
  end

  # When a the utxo is a part of the amount to spend
  # The utxo is fully consumed and the iteration continue utils the the remaining amount to spend are consumed
  defp do_consume_utxos(tx_address, [%UnspentOutput{amount: amount} | rest], remaining, change)
       when amount < remaining do
    do_consume_utxos(tx_address, rest, abs(remaining - amount), change)
  end

  @doc """
  Determines if the ledger operations is valid by rebuilding it from
  the context gathered: transaction, unspent outputs, validation nodes, additional status
  """
  @spec verify?(
          ledger_operations :: __MODULE__.t(),
          tx :: Transaction.pending(),
          unspent_outputs :: list(UnspentOutput.t()),
          validation_node_public_keys :: list(Crypto.key())
        ) :: boolean()
  def verify?(
        ledger_ops = %__MODULE__{
          transaction_movements: transaction_movements,
          unspent_outputs: remaining_utxos,
          fee: fee
        },
        tx = %Transaction{},
        unspent_outputs,
        validation_nodes
      ) do
    expected_fee = Fee.compute(tx)

    if expected_fee != fee do
      false
    else
      with {:ok,
            %__MODULE__{
              transaction_movements: expected_tx_movements,
              unspent_outputs: expected_remaining_utxos
            }} <-
             transaction_movements(
               tx,
               unspent_outputs,
               expected_fee
             ),
           true <- expected_tx_movements == transaction_movements,
           true <- expected_remaining_utxos == remaining_utxos do
        verify_node_movements?(ledger_ops, tx, validation_nodes)
      else
        _ ->
          false
      end
    end
  end

  defp verify_node_movements?(
         %__MODULE__{node_movements: node_movements},
         _tx,
         _validation_nodes
       )
       when length(node_movements) < 2,
       do: false

  defp verify_node_movements?(
         %__MODULE__{fee: fee, node_movements: node_movements},
         tx = %Transaction{},
         validation_nodes
       ) do
    expected_storage_nodes = expected_storage_nodes(tx.previous_public_key)

    [%NodeMovement{to: welcome_node}, %NodeMovement{to: coordinator_node}] =
      Enum.take(node_movements, 2)

    %{nodes: rewarded_nodes, rewards: rewards} = reduce_rewards(node_movements)

    cross_validation_nodes =
      if length(validation_nodes) == 1 do
        validation_nodes
      else
        validation_nodes -- [coordinator_node]
      end

    rewarded_storage_nodes =
      rewarded_nodes
      |> Kernel.--([welcome_node])
      |> Kernel.--([coordinator_node])
      |> Kernel.--(cross_validation_nodes)

    expected_rewards =
      Fee.distribute(
        fee,
        welcome_node,
        coordinator_node,
        cross_validation_nodes,
        rewarded_storage_nodes
      )
      |> Enum.map(& &1.amount)

    cond do
      !Enum.all?(rewarded_storage_nodes, &(&1 in expected_storage_nodes)) ->
        false

      rewards != expected_rewards ->
        false

      Enum.reduce(rewards, 0.0, &(&2 + &1)) != fee ->
        false

      true ->
        true
    end
  end

  defp expected_storage_nodes(previous_public_key) do
    previous_public_key
    |> Crypto.hash()
    |> Election.storage_nodes()
    |> Enum.map(& &1.last_public_key)
  end

  defp reduce_rewards(rewards) do
    Enum.reduce(rewards, %{nodes: [], rewards: []}, fn %NodeMovement{
                                                         to: node_public_key,
                                                         amount: reward
                                                       },
                                                       acc ->
      acc
      |> Map.update!(:nodes, &(&1 ++ [node_public_key]))
      |> Map.update!(:rewards, &(&1 ++ [reward]))
    end)
  end

  @doc """
  Deduct the Input/Output storage nodes for the transaction and node movements
  """
  @spec io_storage_nodes(MODULE.t()) :: list(Node.t())
  def io_storage_nodes(%__MODULE__{
        node_movements: node_movements,
        transaction_movements: transaction_movements
      }) do
    node_movements_addresses =
      node_movements
      |> Enum.reject(&(&1.amount == 0.0))
      |> Enum.map(&Crypto.hash(&1.to))

    transaction_movements_addresses = Enum.map(transaction_movements, & &1.to)

    # Need to inform the involved nodes storage pool (rewards)
    # Need to inform the recipients storage pool (transfers)
    (node_movements_addresses ++
       transaction_movements_addresses)
    |> :lists.flatten()
    |> Enum.uniq()
    |> Enum.map(&Election.storage_nodes/1)
    |> :lists.flatten()
    |> Enum.uniq_by(& &1.last_public_key)
  end

  @doc """
  Serialize a ledger operations

  ## Examples

      iex> Uniris.Transaction.ValidationStamp.LedgerOperations.serialize(%Uniris.Transaction.ValidationStamp.LedgerOperations{
      ...>   fee: 0.1,
      ...>   transaction_movements: [
      ...>     %Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement{
      ...>       to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 10.2
      ...>     }
      ...>   ],
      ...>   node_movements: [
      ...>     %Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement{
      ...>       to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 0.3
      ...>     }
      ...>   ],
      ...>   unspent_outputs: [
      ...>     %Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput{
      ...>       from: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 2.0
      ...>     }
      ...>   ]
      ...> })
      <<
      # Fee
      63, 185, 153, 153, 153, 153, 153, 154,
      # Nb of transaction movements
      1,
      # Transaction movement recipient
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Transaction movement amount
      "@$ffffff",
      # Nb of node movements
      1,
      # Node public key
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Node reward
      63, 211, 51, 51, 51, 51, 51, 51,
      # Nb of unspent outputs
      1,
      # Unspent output origin
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Unspent output amount
      64, 0, 0, 0, 0, 0, 0, 0
      >>
  """
  def serialize(%__MODULE__{
        fee: fee,
        transaction_movements: transaction_movements,
        node_movements: node_movements,
        unspent_outputs: unspent_outputs
      }) do
    bin_transaction_movements =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize/1)
      |> :erlang.list_to_binary()

    bin_node_movements =
      node_movements |> Enum.map(&NodeMovement.serialize/1) |> :erlang.list_to_binary()

    bin_unspent_outputs =
      unspent_outputs |> Enum.map(&UnspentOutput.serialize/1) |> :erlang.list_to_binary()

    <<fee::float, length(transaction_movements)::8, bin_transaction_movements::binary,
      length(node_movements)::8, bin_node_movements::binary, length(unspent_outputs)::8,
      bin_unspent_outputs::binary>>
  end

  @doc """
  Deserialize an encoded ledger operations

  ## Examples

      iex> <<63, 185, 153, 153, 153, 153, 153, 154, 1, 0, 34, 118, 242, 194, 93, 131, 130, 195,
      ...> 9, 97, 237, 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47,
      ...> 158, 139, 207, "@$ffffff", 1, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112,
      ...> 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 63, 211, 51, 51, 51, 51, 51, 51, 1, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237,
      ...> 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 64, 0, 0, 0, 0, 0, 0, 0 >>
      ...> |> Uniris.Transaction.ValidationStamp.LedgerOperations.deserialize()
      {
        %Uniris.Transaction.ValidationStamp.LedgerOperations{
          fee: 0.1,
          transaction_movements: [
            %Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement{
              to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 10.2
            }
          ],
          node_movements: [
            %Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement{
              to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 0.3
            }
          ],
          unspent_outputs: [
            %Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput{
              from: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 2.0
            }
          ]
        },
        ""
      }
  """
  def deserialize(<<fee::float, nb_transaction_movements::8, rest::bitstring>>) do
    {tx_movements, rest} = reduce_transaction_movements(rest, nb_transaction_movements, [])
    <<nb_node_movements::8, rest::bitstring>> = rest
    {node_movements, rest} = reduce_node_movements(rest, nb_node_movements, [])
    <<nb_utxos::8, rest::bitstring>> = rest
    {utxos, rest} = reduce_unspent_outputs(rest, nb_utxos, [])

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        node_movements: node_movements,
        unspent_outputs: utxos
      },
      rest
    }
  end

  defp reduce_transaction_movements(rest, 0, _), do: {[], rest}

  defp reduce_transaction_movements(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_transaction_movements(rest, nb, acc) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest)
    reduce_transaction_movements(rest, nb, [tx_movement | acc])
  end

  defp reduce_node_movements(rest, 0, _), do: {[], rest}

  defp reduce_node_movements(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_node_movements(rest, nb, acc) do
    {node_movement, rest} = NodeMovement.deserialize(rest)
    reduce_node_movements(rest, nb, [node_movement | acc])
  end

  defp reduce_unspent_outputs(rest, 0, _), do: {[], rest}

  defp reduce_unspent_outputs(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_unspent_outputs(rest, nb, acc) do
    {utxo, rest} = UnspentOutput.deserialize(rest)
    reduce_unspent_outputs(rest, nb, [utxo | acc])
  end
end
