defmodule UnirisCore.Mining.Stamp do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Crypto
  alias UnirisCore.Mining.ProofOfWork
  alias UnirisCore.Mining.ProofOfIntegrity
  alias UnirisCore.Mining.Fee
  alias UnirisCore.Election

  @doc """
  Create the validation stamp by the coordinator by producing
  - Proof of Work
  - Proof of integrity
  - Node movements
  - Ledger movements
  """
  @spec create_validation_stamp(
          tx :: Transaction.pending(),
          previous_chain :: list(Transaction.validated()),
          unspent_outputs :: list(Transaction.validated()),
          welcome_node_public_key :: Crypto.key(),
          coordinator_public_key :: Crypto.key(),
          cross_validation_nodes :: list(Crypto.key()),
          previous_storage_nodes :: list(Crypto.key())
        ) :: ValidationStamp.t()
  def create_validation_stamp(
        tx = %Transaction{},
        previous_chain,
        unspent_outputs,
        welcome_node_public_key,
        coordinator_public_key,
        cross_validation_nodes,
        previous_storage_nodes
      ) do
    fee = Fee.compute(tx)

    node_movements =
      NodeMovements.new(
        fee,
        Fee.distribute(
          fee,
          welcome_node_public_key,
          coordinator_public_key,
          cross_validation_nodes,
          previous_storage_nodes
        )
      )

    pow = ProofOfWork.run(tx)
    poi = ProofOfIntegrity.compute([tx | previous_chain])

    ledger_movements =
      LedgerMovements.new(tx, fee, previous_ledger(previous_chain), unspent_outputs)

    ValidationStamp.new(pow, poi, node_movements, ledger_movements)
  end

  defp previous_ledger([]) do
    %LedgerMovements{}
  end

  defp previous_ledger([
         %Transaction{validation_stamp: %ValidationStamp{ledger_movements: ledger_movements}} | _
       ]) do
    ledger_movements
  end

  @doc """
  Create cross validation stamp to validate the validation stamp.

  The stamp is signed according to the following rules:
  - if not inconsistencies, the stamp is signed for the validation stamp integrity
  - otherwise the inconsistencies are signed
  """
  @spec cross_validate(
          tx :: Transaction.pending(),
          stamp :: ValidationStamp.t(),
          coordinator_public_key :: Crypto.key(),
          cross_validation_nodes :: list(Cryptpo.key()),
          previous_chain :: list(Transaction.validated()),
          unspent_outputs :: list(Transaction.validated())
        ) :: Transaction.cross_validation_stamp()
  def cross_validate(
        tx = %Transaction{},
        stamp = %ValidationStamp{},
        coordinator_public_key,
        cross_validation_nodes,
        previous_chain,
        unspent_outputs
      ) do
    case check_validation_stamp(
           tx,
           stamp,
           coordinator_public_key,
           cross_validation_nodes,
           previous_chain,
           unspent_outputs
         ) do
      :ok ->
        create_cross_validation_stamp(stamp, [])

      {:error, inconsistencies} ->
        create_cross_validation_stamp(stamp, inconsistencies)
    end
  end

  def create_cross_validation_stamp(stamp = %ValidationStamp{}, []) do
    sig = Crypto.sign_with_node_key(stamp)
    {sig, [], Crypto.node_public_key()}
  end

  def create_cross_validation_stamp(_stamp, inconsistencies) do
    sig = Crypto.sign_with_node_key(inconsistencies)
    {sig, inconsistencies, Crypto.node_public_key()}
  end

  @doc """
  Check if the cross validation stamps are valid
  """
  @spec valid_cross_validation_stamps?(
          list(Transaction.cross_validation_stamp()),
          ValidationStamp.t()
        ) :: boolean
  def valid_cross_validation_stamps?(
        cross_validation_stamps,
        validation_stamp = %ValidationStamp{}
      ) do
    Enum.all?(cross_validation_stamps, fn cross_stamp ->
      valid_cross_validation_stamp?(cross_stamp, validation_stamp)
    end)
  end

  @doc """
  Determines if a cross validation stamp is valid.

  According to the presence the inconsistencies, these are verify against the signature,
  otherwise it's the validation stamp
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
  Performs a series of checks to ensure the validity of the validation stamp.

  A list of inconsistencies are returned if present.
  """
  @spec check_validation_stamp(
          tx :: Transaction.pending(),
          validation_stamp :: ValidationStamp.t(),
          coordinator_public_key :: Crypto.key(),
          validation_node_public_keys :: list(Crypto.key()),
          previous_chain :: list(Transaction.validated()),
          unspent_outputs :: list(Transaction.validated())
        ) :: :ok | {:error, inconsistencies :: list(atom)}
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
        if ProofOfWork.verify?(tx, pow) do
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
  @spec check_validation_stamp_signature(
          stamp :: ValidationStamp.t(),
          coordinator_public_key :: Crypto.key()
        ) :: :ok | {:error, :invalid_signature}
  def check_validation_stamp_signature(stamp = %ValidationStamp{}, coordinator_public_key) do
    if ValidationStamp.valid_signature?(stamp, coordinator_public_key) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  # Verifies the stamp's proof of integrity from a given chain of transaction by rebuilding it
  # from the previous chain retrieved from the context building.
  @spec check_validation_stamp_proof_of_integrity(
          chain :: [Transaction.pending() | Transaction.validated()],
          proof_of_integrity :: binary()
        ) :: :ok | {:error, :invalid_proof_of_integrity}
  def check_validation_stamp_proof_of_integrity(chain, poi) do
    if ProofOfIntegrity.compute(chain) == poi do
      :ok
    else
      {:error, :invalid_proof_of_integrity}
    end
  end

  @spec check_validation_stamp_fee(tx :: Transaction.pending(), fee :: float()) ::
          :ok | {:error, :invalid_fee}
  def check_validation_stamp_fee(tx = %Transaction{}, fee) do
    if Fee.compute(tx) == fee do
      :ok
    else
      {:error, :invalid_fee}
    end
  end

  # Verify the node movements rewards by rebuilding the reward fee distribution with the expected
  # previous storage nodes by validators.
  @spec check_validation_stamp_rewards(
          Transaction.pending(),
          validation_node_public_keys :: list(Crypto.key()),
          rewards :: list(NodeMovements.reward())
        ) :: :ok | {:error, :invalid_rewarded_nodes} | {:error, :invalid_reward_distributions}
  def check_validation_stamp_rewards(_, _, []) do
    {:error, :invalid_rewarded_nodes}
  end

  def check_validation_stamp_rewards(tx = %Transaction{}, validation_node_public_keys, rewards)
      when is_list(rewards) and length(rewards) >= 2 do
    fee = Fee.compute(tx)

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
      Fee.distribute(
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

  # Verify the ledger movement from the validation stamp by rebuilding the UTXO next ledger from context building
  # data such as previous ledger, unspent outputs
  @spec check_validation_stamp_ledger_movements(
          tx :: Transaction.pending(),
          previous_ledger :: LedgerMovements.t(),
          unspent_outputs :: list(Transaction.validated()),
          next_ledger :: LedgerMovements.t()
        ) :: :ok | {:error, :invalid_ledger_movements}
  def check_validation_stamp_ledger_movements(
        tx = %Transaction{},
        previous_ledger = %LedgerMovements{},
        unspent_outputs,
        next_ledger = %LedgerMovements{}
      ) do
    fee = Fee.compute(tx)

    ledger = LedgerMovements.new(tx, fee, previous_ledger, unspent_outputs)

    if ledger == next_ledger do
      :ok
    else
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
  Determines if the atomic commitment is reached for the cross validate stamps
  """
  @spec atomic_commitment?(cross_validation_stamps :: list(Transaction.cross_validation_stamp())) ::
          boolean()
  def atomic_commitment?(cross_validation_stamps) do
    Enum.dedup_by(cross_validation_stamps, fn {_, inconsistencies, _} -> inconsistencies end)
    |> length
    |> case do
      1 ->
        true

      _ ->
        false
    end
  end
end
