defmodule Archethic.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use GenServer

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.PendingTransactionValidation
  alias Archethic.Mining.TransactionContext
  alias Archethic.Mining.ValidationContext
  alias Archethic.Mining.WorkflowRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicateTransactionChain
  alias Archethic.P2P.Message.ValidationError
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(arg) do
    tx = Keyword.get(arg, :transaction)
    Registry.register(WorkflowRegistry, tx.address, [])
    {:ok, %{}, {:continue, {:start_mining, tx}}}
  end

  def handle_continue({:start_mining, tx}, _state) do
    Logger.info("Start mining",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validation_time = DateTime.utc_now()
    current_node = P2P.get_node_info()

    authorized_nodes = P2P.authorized_nodes(validation_time)

    chain_storage_nodes =
      Election.chain_storage_nodes_with_type(
        tx.address,
        tx.type,
        authorized_nodes
      )

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
        |> Enum.map(fn {_origin, resolved} -> resolved end)
        |> Enum.concat([LedgerOperations.burning_address()])
        |> Election.io_storage_nodes(authorized_nodes)
      end

    {prev_tx, unspent_outputs, previous_storage_nodes, chain_storage_nodes_view,
     beacon_storage_nodes_view,
     io_storage_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        Enum.map(chain_storage_nodes, & &1.first_public_key),
        Enum.map(beacon_storage_nodes, & &1.first_public_key),
        Enum.map(io_storage_nodes, & &1.first_public_key)
      )

    valid_pending_transaction? =
      case PendingTransactionValidation.validate(tx) do
        :ok ->
          true

        _ ->
          false
      end

    validation_context =
      ValidationContext.new(
        transaction: tx,
        welcome_node: current_node,
        coordinator_node: current_node,
        cross_validation_nodes: [current_node],
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: io_storage_nodes,
        validation_time: validation_time,
        resolved_addresses: resolved_addresses
      )
      |> ValidationContext.set_pending_transaction_validation(valid_pending_transaction?)
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

    {:noreply,
     %{
       context: validation_context,
       confirmations: []
     }}
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.confirm_validation_node(Crypto.last_node_public_key())
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.create_replication_tree()
    |> ValidationContext.cross_validate()
  end

  defp start_replication(context = %ValidationContext{}) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    replication_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send transaction to storage nodes: #{Enum.map_join(replication_nodes, ",", &Node.endpoint/1)}",
      transaction_address: Base.encode16(validated_tx.address),
      transaction_type: validated_tx.type
    )

    P2P.broadcast_message(replication_nodes, %ReplicateTransactionChain{
      transaction: validated_tx,
      replying_node: Crypto.first_node_public_key()
    })
  end

  def handle_info(
        {:replication_error, reason},
        state = %{context: %ValidationContext{transaction: %Transaction{address: tx_address}}}
      ) do
    Logger.warning("Invalid transaction #{inspect(reason)}")
    # notify welcome node
    message = %ValidationError{address: tx_address, reason: reason}

    Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
      P2P.send_message(
        Crypto.last_node_public_key(),
        message
      )
    end)

    {:stop, :normal, state}
  end

  def handle_info(
        {:ack_replication, signature, node_public_key},
        state = %{context: context = %ValidationContext{transaction: tx}}
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
        notify(new_state)
        {:noreply, new_state}
      else
        {:noreply, new_state}
      end
    else
      _reason ->
        Logger.warning("Invalid storage ack",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type,
          node: Base.encode16(node_public_key)
        )

        {:noreply, state}
    end
  end

  defp notify(%{context: context}) do
    notify_attestation(context)
    notify_io_nodes(context)
  end

  defp notify_attestation(
         context = %ValidationContext{
           welcome_node: welcome_node,
           storage_nodes_confirmations: confirmations
         }
       ) do
    validated_tx = ValidationContext.get_validated_transaction(context)
    tx_summary = TransactionSummary.from_transaction(validated_tx)

    attestation = %ReplicationAttestation{
      transaction_summary: tx_summary,
      confirmations: confirmations
    }

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
    |> P2P.broadcast_message(
      if Transaction.network_type?(validated_tx.type),
        do: %ReplicateTransactionChain{
          transaction: validated_tx
        },
        else: %ReplicateTransaction{transaction: validated_tx}
    )
  end
end
