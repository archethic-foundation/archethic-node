defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Set of the ledger operations taken by the network (transaction movements, node rewards, unspent outputs, fee)
  defined during the transaction mining
  """

  defstruct transaction_movements: [],
            node_movements: [],
            unspent_outputs: [],
            fee: 0.0

  alias __MODULE__.Movement
  alias __MODULE__.UnspentOutput
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.Mining.Fee
  alias UnirisCore.Crypto
  alias UnirisCore.Election

  @type t() :: %__MODULE__{
          transaction_movements: list(Movement.t()),
          node_movements: list(Movement.t()),
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
          %Movement{to: to, amount: amount}
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
    [%Movement{to: welcome_node}, %Movement{to: coordinator_node}] = Enum.take(node_movements, 2)
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
    Enum.reduce(rewards, %{nodes: [], rewards: []}, fn %Movement{
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
    |> Enum.uniq()
  end
end
