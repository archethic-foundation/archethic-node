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

  alias Archethic.Mining.PendingTransactionValidation
  alias Archethic.Mining.TransactionContext
  alias Archethic.Mining.ValidationContext
  alias Archethic.Mining.WorkflowRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.NotifyPreviousChain
  alias Archethic.P2P.Message.ReplicationAttestationMessage
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicatePendingTransactionChain
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.ValidationError
  alias Archethic.P2P.Message.ValidateTransaction
  alias Archethic.P2P.Message.UnlockChain
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
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

    resolved_addresses = TransactionChain.resolve_transaction_addresses(tx, validation_time)

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
        io_storage_nodes: io_storage_nodes,
        validation_time: validation_time,
        resolved_addresses: resolved_addresses,
        contract_context: contract_context
      )

    validation_context =
      case PendingTransactionValidation.validate(tx, validation_time) do
        :ok ->
          ValidationContext.set_pending_transaction_validation(validation_context, true)

        {:error, reason} ->
          ValidationContext.set_pending_transaction_validation(validation_context, false, reason)
      end

    validation_context =
      validation_context
      |> ValidationContext.put_transaction_context(
        prev_tx,
        unspent_outputs,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      )
      |> validate()

    start_replication(validation_context)

    new_state =
      state
      |> Map.put(:context, validation_context)
      |> Map.put(:confirmations, [])

    {:noreply, new_state, @mining_timeout}
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.confirm_validation_node(Crypto.last_node_public_key())
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.create_replication_tree()
    |> ValidationContext.cross_validate()
  end

  defp start_replication(context = %ValidationContext{contract_context: contract_context}) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    replication_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send transaction to storage nodes: #{Enum.map_join(replication_nodes, ",", &Node.endpoint/1)} for replication's validation",
      transaction_address: Base.encode16(validated_tx.address),
      transaction_type: validated_tx.type
    )

    message = %ValidateTransaction{
      transaction: validated_tx,
      contract_context: contract_context
    }

    results =
      Task.Supervisor.async_stream_nolink(
        Archethic.TaskSupervisor,
        replication_nodes,
        &P2P.send_message(&1, message),
        ordered: false,
        on_timeout: :kill_task,
        timeout: Message.get_timeout(message) + 2000
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, {:ok, res}} -> res end)
      |> Enum.to_list()

    if Enum.all?(results, &match?(%Ok{}, &1)) do
      Logger.info(
        "Send replication chain message to storage nodes: #{Enum.map_join(replication_nodes, ",", &Node.endpoint/1)}",
        transaction_address: Base.encode16(validated_tx.address),
        transaction_type: validated_tx.type
      )

      P2P.broadcast_message(replication_nodes, %ReplicatePendingTransactionChain{
        address: validated_tx.address
      })
    else
      errors = Enum.filter(results, &match?(%ReplicationError{}, &1))

      case Enum.dedup(errors) do
        [%ReplicationError{reason: reason}] ->
          send(self(), {:replication_error, reason})

        _ ->
          send(self(), {:replication_error, :invalid_atomic_commitment})
      end
    end
  end

  def handle_info(
        {:replication_error, reason},
        state = %{
          context:
            context = %ValidationContext{
              transaction: %Transaction{address: tx_address},
              pending_transaction_error_detail: pending_error_detail
            }
        }
      ) do
    {error_context, error_reason} =
      case reason do
        :invalid_pending_transaction ->
          {:invalid_transaction, pending_error_detail}

        :invalid_inherit_constraints ->
          {:invalid_transaction, "Inherit constraints not respected"}

        :insufficient_funds ->
          {:invalid_transaction, "Insufficient funds"}

        :invalid_proof_of_work ->
          {:invalid_transaction, "Invalid origin signature"}

        reason ->
          {:network_issue, reason |> Atom.to_string() |> String.replace("_", " ")}
      end

    Logger.warning("Invalid transaction #{inspect(reason)}",
      transaction_address: Base.encode16(tx_address)
    )

    Logger.debug("Notify error back to the welcome node",
      transaction_address: Base.encode16(tx_address)
    )

    # Notify error to the welcome node
    message = %ValidationError{address: tx_address, context: error_context, reason: error_reason}

    Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
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
    message = %ValidationError{context: :network_issue, reason: "timeout", address: tx.address}

    Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
      P2P.send_message(
        welcome_node,
        message
      )

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

  defp notify_io_nodes(context = %ValidationContext{}) do
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
