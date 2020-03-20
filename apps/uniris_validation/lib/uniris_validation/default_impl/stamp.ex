defmodule UnirisValidation.DefaultImpl.Stamp do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisValidation.DefaultImpl.Reward
  alias UnirisValidation.DefaultImpl.Fee
  alias UnirisValidation.DefaultImpl.ProofOfIntegrity
  alias UnirisValidation.DefaultImpl.ProofOfWork
  alias UnirisValidation.DefaultImpl.UTXO
  alias UnirisCrypto, as: Crypto
  alias UnirisElection, as: Election

  @typep pow_result :: {:ok, binary()} | {:error, :not_found}

  @doc """
  Create a new validation stamp based on data coming from the mining
  """
  @spec create_validation_stamp(
          transaction :: Transaction.pending(),
          previous_chain :: list(Transaction.validated()),
          unspent_outputs :: list(Transaction.validated()),
          welcome_node :: binary(),
          coordinator_node :: binary(),
          cross_validation_nodes :: list(binary()),
          previous_storage_nodes :: list(binary()),
          proof_of_work :: pow_result
        ) :: ValidationStamp.t()
  def create_validation_stamp(
        tx = %Transaction{},
        previous_chain,
        unspent_outputs,
        welcome_node,
        coordinator_node,
        cross_validation_nodes,
        previous_storage_nodes,
        pow_result
      ) do
    fee = Fee.from_transaction(tx)
    previous_ledger = previous_ledger(previous_chain)
    ledger_movements = next_ledger(tx, fee, previous_ledger, unspent_outputs)

    node_movements = %NodeMovements{
      fee: fee,
      rewards:
        Reward.distribute_fee(
          fee,
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        )
    }

    ValidationStamp.new(
      reduce_proof_of_work_result(pow_result),
      ProofOfIntegrity.from_chain([tx | previous_chain]),
      ledger_movements,
      node_movements
    )
  end

  defp previous_ledger([]) do
    %LedgerMovements{}
  end

  defp previous_ledger([
         %Transaction{validation_stamp: %ValidationStamp{ledger_movements: ledger_movements}}
       ]) do
    ledger_movements
  end

  defp next_ledger(tx = %Transaction{}, fee, previous_ledger, unspent_outputs) do
    case UTXO.next_ledger(tx, fee, previous_ledger, unspent_outputs) do
      {:ok, ledger} ->
        ledger

      _ ->
        previous_ledger
    end
  end

  defp reduce_proof_of_work_result({:ok, pow}) do
    pow
  end

  defp reduce_proof_of_work_result({:error, :not_found}) do
    ""
  end

  @doc """
  Validate a validation stamp and return a list of inconsistencies when subsets checks are invalid

  Each subset verification is run independently and concurrently and aggregated together to produce a list of inconsistencies
  """
  @spec check_validation_stamp(
          Transaction.pending(),
          ValidationStamp.t(),
          binary(),
          list(binary()),
          list(Transaction.validated()),
          list(Transaction.validated())
        ) :: :ok | {:error, list(atom)}
  def check_validation_stamp(
        tx = %Transaction{},
        stamp = %ValidationStamp{
          proof_of_work: pow,
          proof_of_integrity: poi,
          ledger_movements: next_ledger,
          node_movements: %NodeMovements{fee: fee, rewards: rewards}
        },
        coordinator_public_key,
        validation_nodes,
        previous_chain,
        unspent_outputs
      ) do
    [
      fn -> check_validation_stamp_signature(stamp, coordinator_public_key) end,
      fn ->
        if ProofOfWork.verify(tx, pow) do
          :ok
        else
          {:error, :invalid_proof_of_work}
        end
      end,
      fn -> check_validation_stamp_proof_of_integrity([tx | previous_chain], poi) end,
      fn -> check_validation_stamp_fee(tx, fee) end,
      fn ->
        check_validation_stamp_ledger_movements(
          tx,
          previous_ledger(previous_chain),
          unspent_outputs,
          next_ledger
        )
      end,
      fn -> check_validation_stamp_rewards(tx, validation_nodes, rewards) end
    ]
    |> Task.async_stream(& &1.())
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.reject(fn res -> match?(:ok, res) end)
    |> case do
      [] ->
        :ok

      inconsistencies ->
        {:error, Enum.map(inconsistencies, fn {_, reason} -> reason end)}
    end
  end

  @doc """
  Verify the stamp signature from the coordinator public key
  """
  def check_validation_stamp_signature(stamp = %ValidationStamp{}, coordinator_public_key) do
    if ValidationStamp.valid_signature?(stamp, coordinator_public_key) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @doc """
  Verifies the stamp's proof of integrity from a given chain of transaction by rebuilding it
  from the previous chain retrieved from the context building.
  """
  def check_validation_stamp_proof_of_integrity(chain, poi) do
    if ProofOfIntegrity.from_chain(chain) == poi do
      :ok
    else
      {:error, :invalid_proof_of_integrity}
    end
  end

  @doc """
  Verify the transaction fee from the validation stamp
  """
  def check_validation_stamp_fee(tx = %Transaction{}, fee) do
    if Fee.from_transaction(tx) == fee do
      :ok
    else
      {:error, :invalid_fee}
    end
  end

  @doc """
  Verify the node movements rewards by rebuilding the reward fee distribution with the expected
  previous storage nodes by validators.

  """
  def check_validation_stamp_rewards(_, _, []) do
    {:error, :invalid_rewarded_nodes}
  end

  def check_validation_stamp_rewards(tx = %Transaction{}, validation_node_public_keys, rewards)
      when is_list(rewards) and length(rewards) >= 2 do
    fee = Fee.from_transaction(tx)

    expected_storage_nodes = expected_storage_nodes(tx.previous_public_key)

    [{welcome_node, _}, {coordinator_node, _}] = Enum.take(rewards, 2)

    %{nodes: rewarded_nodes, rewards: rewards} = reduce_rewards(rewards)

    validation_node_public_keys =
      if length(validation_node_public_keys) == 1 do
        validation_node_public_keys
      else
        validation_node_public_keys -- [coordinator_node]
      end

    rewarded_storage_nodes =
      rewarded_nodes
      |> Kernel.--([welcome_node])
      |> Kernel.--([coordinator_node])
      |> Kernel.--(validation_node_public_keys)

    if Enum.all?(rewarded_storage_nodes, &(&1 in expected_storage_nodes)) do
      Reward.distribute_fee(
        fee,
        welcome_node,
        coordinator_node,
        validation_node_public_keys,
        rewarded_storage_nodes
      )
      |> Enum.map(fn {_, distribution} -> distribution end)
      |> case do
        distributed_rewards when rewards == distributed_rewards ->
          :ok

        _ ->
          {:error, :invalid_reward_distributions}
      end
    else
      {:error, :invalid_rewarded_nodes}
    end
  end

  @doc """
  Verify the ledger movement from the validation stamp by rebuilding the UTXO next ledger from context building
  data such as previous ledger, unspent outputs
  """
  def check_validation_stamp_ledger_movements(
        tx = %Transaction{},
        previous_ledger = %LedgerMovements{},
        unspent_outputs,
        next_ledger = %LedgerMovements{}
      ) do
    fee = Fee.from_transaction(tx)

    case UTXO.next_ledger(tx, fee, previous_ledger, unspent_outputs) do
      {:ok, expected_next_ledger = %LedgerMovements{}} when expected_next_ledger == next_ledger ->
        :ok

      _ ->
        {:error, :invalid_ledger_movements}
    end
  end

  defp expected_storage_nodes(previous_public_key) do
    previous_public_key
    |> Crypto.hash()
    |> Election.storage_nodes()
    |> Enum.map(& &1.last_public_key)
  end

  defp reduce_rewards(rewards) do
    Enum.reduce(rewards, %{nodes: [], rewards: []}, fn {key, reward}, acc ->
      acc
      |> Map.update!(:nodes, &(&1 ++ [key]))
      |> Map.update!(:rewards, &(&1 ++ [reward]))
    end)
  end

  @doc """
  Create a cross validation stamp by signing either the validation stamp or inconsistencies if any.
  """
  def create_cross_validation_stamp(stamp = %ValidationStamp{}, [], node_public_key) do
    sig = Crypto.sign_with_node_key(stamp)
    {sig, [], node_public_key}
  end

  def create_cross_validation_stamp(_stamp, inconsistencies, node_public_key) do
    sig = Crypto.sign_with_node_key(inconsistencies)
    {sig, inconsistencies, node_public_key}
  end

  @doc """
  Verify the integrity of the a cross validation stamp by
  checking its signature according to the stamp or inconsistencies if any
  """
  @spec valid_cross_validation_stamp?(
          Transaction.cross_validation_stamp(),
          ValidationStamp.t()
        ) :: boolean()
  def valid_cross_validation_stamp?(
        {signature, inconsistencies, node_public_key},
        stamp = %ValidationStamp{}
      ) do
    case inconsistencies do
      [] ->
        Crypto.verify(signature, stamp, node_public_key)

      _ ->
        Crypto.verify(signature, inconsistencies, node_public_key)
    end
  end

  @doc """
  Verify if all the cross validation stamps are valid
  """
  @spec valid_cross_validation_stamps?(
          list(Transaction.cross_validation_stamp()),
          ValidationStamp.t()
        ) :: boolean
  def valid_cross_validation_stamps?(cross_stamps, stamp = %ValidationStamp{}) do
    Enum.all?(cross_stamps, fn cross_stamp ->
      valid_cross_validation_stamp?(cross_stamp, stamp)
    end)
  end
end
