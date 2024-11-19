defmodule Archethic.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use GenServer
  @vsn 1

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Mining.Error
  alias Archethic.Mining.TransactionContext
  alias Archethic.Mining.ValidationContext
  alias Archethic.Mining.WorkflowRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Message.NotifyPreviousChain
  alias Archethic.P2P.Message.ReplicationAttestationMessage
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicatePendingTransactionChain
  alias Archethic.P2P.Message.ValidationError
  alias Archethic.P2P.Message.ValidateTransaction
  alias Archethic.P2P.Message.UnlockChain
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  @mining_timeout Application.compile_env!(:archethic, [__MODULE__, :global_timeout])

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(arg) do
    tx = Keyword.get(arg, :transaction)
    welcome_node = Keyword.fetch!(arg, :welcome_node)
    contract_context = Keyword.get(arg, :contract_context)
    ref_timestamp = Keyword.get(arg, :ref_timestamp)

    Registry.register(WorkflowRegistry, tx.address, [])

    Logger.info("Start mining",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {:ok, %{start_time: System.monotonic_time(), welcome_node: welcome_node},
     {:continue, {:start_mining, tx, contract_context, ref_timestamp}}}
  end

  def handle_continue(
        {:start_mining, tx, contract_context, ref_timestamp},
        state = %{welcome_node: welcome_node}
      ) do
    start = System.monotonic_time()

    Logger.info("Retrieve transaction context",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validation_time = ref_timestamp |> DateTime.truncate(:millisecond)

    current_node = P2P.get_node_info()
    authorized_nodes = [current_node]

    tx_context = TransactionContext.get(tx, validation_time, authorized_nodes)

    :telemetry.execute([:archethic, :mining, :fetch_context], %{
      duration: System.monotonic_time() - start
    })

    prev_tx = Keyword.get(tx_context, :previous_transaction)
    unspent_outputs = Keyword.get(tx_context, :unspent_outputs)

    Logger.debug("Previous transaction #{inspect(prev_tx)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    Logger.debug("Unspent outputs #{inspect(unspent_outputs)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    Logger.info("Transaction context retrieved",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validation_context =
      [
        transaction: tx,
        welcome_node: welcome_node,
        coordinator_node: current_node,
        cross_validation_nodes: [current_node],
        validation_time: validation_time,
        contract_context: contract_context,
        proof_elected_nodes: ProofOfValidation.get_election(authorized_nodes, tx.address)
      ]
      |> Keyword.merge(tx_context)
      |> ValidationContext.new()

    :telemetry.execute([:archethic, :mining, :fetch_context], %{
      duration: System.monotonic_time() - start
    })

    validation_context = ValidationContext.validate_pending_transaction(validation_context)

    validation_context =
      %ValidationContext{mining_error: mining_error} =
      validation_context
      |> ValidationContext.add_aggregated_utxos(unspent_outputs)
      |> validate()

    if mining_error == nil,
      do: request_replication_validation(validation_context),
      else: send(self(), {:validation_error, mining_error})

    new_state = state |> Map.put(:context, validation_context) |> Map.put(:confirmations, [])

    {:noreply, new_state, @mining_timeout}
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.confirm_validation_node(Crypto.first_node_public_key())
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.create_replication_tree()
    |> ValidationContext.cross_validate()
  end

  defp request_replication_validation(
         context = %ValidationContext{
           transaction: tx,
           contract_context: contract_context,
           aggregated_utxos: aggregated_utxos,
           cross_validation_stamps: cross_stamps
         }
       ) do
    storage_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send validated transaction to #{Enum.map_join(storage_nodes, ",", &Node.endpoint/1)} for replication's validation",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validated_tx = ValidationContext.get_validated_transaction(context)

    message = %ValidateTransaction{
      transaction: validated_tx,
      contract_context: contract_context,
      inputs: aggregated_utxos,
      cross_validation_stamps: cross_stamps
    }

    P2P.broadcast_message(storage_nodes, message)
  end

  defp request_replication(
         context = %ValidationContext{
           transaction: %Transaction{address: tx_address, type: type},
           proof_of_validation: proof_of_validation
         }
       ) do
    replication_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send replication chain message to storage nodes: #{Enum.map_join(replication_nodes, ",", &Node.endpoint/1)}",
      transaction_address: Base.encode16(tx_address),
      transaction_type: type
    )

    P2P.broadcast_message(replication_nodes, %ReplicatePendingTransactionChain{
      address: tx_address,
      proof_of_validation: proof_of_validation
    })
  end

  def handle_info(
        {:add_cross_validation_stamp, cross_validation_stamp = %CrossValidationStamp{}},
        state = %{
          context:
            context = %ValidationContext{
              transaction: %Transaction{address: tx_address, type: type}
            }
        }
      ) do
    Logger.info("Add cross replication stamp",
      transaction_address: Base.encode16(tx_address),
      transaction_type: type
    )

    new_context = ValidationContext.add_cross_validation_stamp(context, cross_validation_stamp)

    new_state = Map.put(state, :context, new_context)

    case ValidationContext.get_cross_validation_state(new_context) do
      :reached ->
        Logger.info("Create proof of validation",
          transaction_address: Base.encode16(tx_address),
          transaction_type: type
        )

        new_context = ValidationContext.create_proof_of_validation(context)
        request_replication(new_context)
        {:noreply, Map.put(state, :context, new_context)}

      :not_reached ->
        {:noreply, new_state}

      :error ->
        error = Error.new(:consensus_not_reached, "Invalid atomic commitment")
        send(self(), {:validation_error, error})
        {:noreply, new_state}
    end
  end

  def handle_info(
        {:validation_error, error},
        state = %{
          context: context = %ValidationContext{transaction: %Transaction{address: tx_address}}
        }
      ) do
    Logger.warning("Invalid transaction #{inspect(error)}",
      transaction_address: Base.encode16(tx_address)
    )

    Logger.debug("Notify error back to the welcome node",
      transaction_address: Base.encode16(tx_address)
    )

    # Notify error to the welcome node
    message = %ValidationError{address: tx_address, error: error}

    Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
      P2P.send_message(Crypto.first_node_public_key(), message)
    end)

    # Notify storage nodes to unlock chain
    message = %UnlockChain{address: tx_address}

    context |> ValidationContext.get_chain_replication_nodes() |> P2P.broadcast_message(message)

    {:stop, :normal, state}
  end

  def handle_info(
        {:ack_replication, signature, node_public_key},
        state = %{
          start_time: start_time,
          context:
            context = %ValidationContext{
              transaction: %Transaction{address: address, type: type},
              validation_time: validation_time
            }
        }
      ) do
    with {:ok, node_index} <-
           ValidationContext.get_chain_storage_position(context, node_public_key),
         validated_tx <- ValidationContext.get_validated_transaction(context),
         tx_summary <- TransactionSummary.from_transaction(validated_tx),
         true <-
           Crypto.verify?(signature, TransactionSummary.serialize(tx_summary), node_public_key) do
      new_context = ValidationContext.add_storage_confirmation(context, node_index, signature)

      new_state = %{state | context: new_context}

      if ValidationContext.enough_storage_confirmations?(new_context) do
        duration = System.monotonic_time() - start_time

        # send the mining_completed event
        Archethic.PubSub.notify_mining_completed(address, validation_time, duration, true)

        # metrics
        :telemetry.execute([:archethic, :mining, :full_transaction_validation], %{
          duration: duration
        })

        notify(new_state)
        {:stop, :normal, new_state}
      else
        {:noreply, new_state}
      end
    else
      _reason ->
        Logger.warning("Invalid storage ack",
          transaction_address: Base.encode16(address),
          transaction_type: type,
          node: Base.encode16(node_public_key)
        )

        {:noreply, state}
    end
  end

  def handle_info(
        :timeout,
        state = %{context: %ValidationContext{transaction: tx, welcome_node: welcome_node}}
      ) do
    Logger.warning("Timeout reached during mining",
      transaction_type: tx.type,
      transaction_address: Base.encode16(tx.address)
    )

    # Notify error to the welcome node
    message = %ValidationError{error: Error.new(:timeout), address: tx.address}

    Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
      P2P.send_message(welcome_node, message)
      :ok
    end)

    {:stop, :normal, state}
  end

  defp notify(%{context: context}) do
    notify_attestation(context)
    notify_io_nodes(context)
    notify_previous_chain(context)

    :ok
  end

  defp notify_attestation(
         context = %ValidationContext{
           welcome_node: welcome_node,
           storage_nodes_confirmations: confirmations
         }
       ) do
    validated_tx = ValidationContext.get_validated_transaction(context)
    tx_summary = TransactionSummary.from_transaction(validated_tx)

    attestation =
      ReplicationAttestationMessage.from_replication_attestation(%ReplicationAttestation{
        transaction_summary: tx_summary,
        confirmations: confirmations
      })

    beacon_storage_nodes = ValidationContext.get_beacon_replication_nodes(context)

    [welcome_node | beacon_storage_nodes]
    |> P2P.distinct_nodes()
    |> tap(fn nodes ->
      Logger.debug("Send attestation to #{Enum.map_join(nodes, ",", &Node.endpoint/1)}",
        transaction_address: Base.encode16(tx_summary.address),
        transaction_type: tx_summary.type
      )
    end)
    |> P2P.broadcast_message(attestation)
  end

  defp notify_io_nodes(context) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    context
    |> ValidationContext.get_io_replication_nodes()
    |> tap(fn nodes ->
      Logger.debug(
        "Send transaction to IO nodes: #{Enum.map_join(nodes, ",", &Node.endpoint/1)}",
        transaction_address: Base.encode16(validated_tx.address),
        transaction_type: validated_tx.type
      )
    end)
    |> P2P.broadcast_message(%ReplicateTransaction{transaction: validated_tx})
  end

  defp notify_previous_chain(
         context = %ValidationContext{
           transaction: tx
         }
       ) do
    unless Transaction.network_type?(tx.type) do
      context
      |> ValidationContext.get_confirmed_replication_nodes()
      |> P2P.broadcast_message(%NotifyPreviousChain{address: tx.address})
    end
  end
end
