defmodule Archethic.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use GenServer
  @vsn 1

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Election

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

  alias Archethic.TransactionChain
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

    Registry.register(WorkflowRegistry, tx.address, [])

    {:ok, %{start_time: System.monotonic_time(), welcome_node: welcome_node},
     {:continue, {:start_mining, tx, contract_context}}}
  end

  def handle_continue(
        {:start_mining, tx, contract_context},
        state = %{welcome_node: welcome_node}
      ) do
    Logger.info("Start mining",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validation_time = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    current_node = P2P.get_node_info()

    authorized_nodes = [current_node]

    chain_storage_nodes = Election.chain_storage_nodes(tx.address, authorized_nodes)

    beacon_storage_nodes =
      Election.beacon_storage_nodes(
        BeaconChain.subset_from_address(tx.address),
        BeaconChain.next_slot(DateTime.utc_now()),
        authorized_nodes
      )

    resolved_addresses = TransactionChain.resolve_transaction_addresses!(tx)

    previous_address = Transaction.previous_address(tx)
    previous_storage_nodes = Election.chain_storage_nodes(previous_address, authorized_nodes)

    {:ok, genesis_address} =
      TransactionChain.fetch_genesis_address(previous_address, previous_storage_nodes)

    genesis_storage_nodes = Election.chain_storage_nodes(genesis_address, authorized_nodes)

    io_storage_nodes =
      if Transaction.network_type?(tx.type) do
        P2P.list_nodes()
      else
        resolved_addresses
        |> Map.values()
        |> Election.io_storage_nodes(authorized_nodes)
      end

    start = System.monotonic_time()

    {prev_tx, unspent_outputs, previous_storage_nodes, chain_storage_nodes_view,
     beacon_storage_nodes_view,
     io_storage_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        genesis_address,
        Enum.map(chain_storage_nodes, & &1.first_public_key),
        Enum.map(beacon_storage_nodes, & &1.first_public_key),
        Enum.map(io_storage_nodes, & &1.first_public_key)
      )

    :telemetry.execute([:archethic, :mining, :fetch_context], %{
      duration: System.monotonic_time() - start
    })

    validation_context =
      ValidationContext.new(
        transaction: tx,
        welcome_node: welcome_node,
        coordinator_node: current_node,
        cross_validation_nodes: [current_node],
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: P2P.distinct_nodes(io_storage_nodes ++ genesis_storage_nodes),
        validation_time: validation_time,
        resolved_addresses: resolved_addresses,
        contract_context: contract_context,
        genesis_address: genesis_address,
        proof_elected_nodes: ProofOfValidation.get_election(authorized_nodes, tx.address)
      )

    validation_context = ValidationContext.validate_pending_transaction(validation_context)

    validation_context =
      %ValidationContext{mining_error: mining_error} =
      validation_context
      |> ValidationContext.put_transaction_context(
        prev_tx,
        unspent_outputs,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      )
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
    |> ValidationContext.confirm_validation_node(Crypto.last_node_public_key())
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.create_replication_tree()
    |> ValidationContext.cross_validate()
  end

  defp request_replication_validation(
         context = %ValidationContext{
           transaction: tx,
           contract_context: contract_context,
           aggregated_utxos: aggregated_utxos
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
      inputs: aggregated_utxos
    }

    P2P.broadcast_message(storage_nodes, message)
  end

  defp request_replication(
         context = %ValidationContext{
           transaction: %Transaction{address: tx_address, type: type},
           genesis_address: genesis_address,
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
      genesis_address: genesis_address,
      proof_of_validation: proof_of_validation
    })
  end

  def handle_info(
        {:add_cross_validation_stamp, cross_validation_stamp = %CrossValidationStamp{}, from},
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

    new_context =
      ValidationContext.add_cross_validation_stamp(context, cross_validation_stamp, from)

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
      P2P.send_message(
        Crypto.last_node_public_key(),
        message
      )
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
              validation_time: validation_time,
              genesis_address: genesis_address
            }
        }
      ) do
    with {:ok, node_index} <-
           ValidationContext.get_chain_storage_position(context, node_public_key),
         validated_tx <- ValidationContext.get_validated_transaction(context),
         tx_summary <- TransactionSummary.from_transaction(validated_tx, genesis_address),
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
           storage_nodes_confirmations: confirmations,
           genesis_address: genesis_address
         }
       ) do
    validated_tx = ValidationContext.get_validated_transaction(context)
    tx_summary = TransactionSummary.from_transaction(validated_tx, genesis_address)

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

  defp notify_io_nodes(
         context = %ValidationContext{
           genesis_address: genesis_address,
           proof_of_validation: proof_of_validation
         }
       ) do
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
    |> P2P.broadcast_message(%ReplicateTransaction{
      transaction: validated_tx,
      genesis_address: genesis_address,
      proof_of_validation: proof_of_validation
    })
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
