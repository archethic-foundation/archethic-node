defmodule Archethic.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use Task

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.PendingTransactionValidation
  alias Archethic.Mining.TransactionContext
  alias Archethic.Mining.ValidationContext

  alias Archethic.P2P
  alias Archethic.P2P.Message.AcknowledgeStorage
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicateTransactionChain
  alias Archethic.P2P.Node

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  def start_link(opts \\ []) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(opts) do
    tx = Keyword.get(opts, :transaction)

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
    |> replicate_and_aggregate_confirmations()
    |> notify()
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.confirm_validation_node(Crypto.last_node_public_key())
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.create_replication_tree()
    |> ValidationContext.cross_validate()
  end

  defp replicate_and_aggregate_confirmations(context = %ValidationContext{}) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    replication_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send transaction to storage nodes: #{Enum.map_join(replication_nodes, ",", &Node.endpoint/1)}",
      transaction_address: Base.encode16(validated_tx.address),
      transaction_type: validated_tx.type
    )

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      replication_nodes,
      fn node ->
        {P2P.send_message(node, %ReplicateTransactionChain{
           transaction: validated_tx
         }), node}
      end,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Stream.filter(&match?({:ok, {{:ok, _res}, _node}}, &1))
    |> Stream.map(fn {:ok, {{:ok, res}, node}} -> {res, node} end)
    |> Enum.reduce(
      %{
        confirmations: [],
        context: context,
        transaction_summary: TransactionSummary.from_transaction(validated_tx)
      },
      &reduce_confirmations/2
    )
  end

  defp reduce_confirmations(
         {%AcknowledgeStorage{
            signature: signature
          }, %Node{first_public_key: node_public_key}},
         acc = %{transaction_summary: tx_summary, context: context}
       ) do
    if Crypto.verify?(signature, TransactionSummary.serialize(tx_summary), node_public_key) do
      {:ok, position} = ValidationContext.get_chain_storage_position(context, node_public_key)
      Map.update!(acc, :confirmations, &[{position, signature} | &1])
    else
      acc
    end
  end

  defp reduce_confirmations(
         {%Error{reason: reason}, _},
         _acc = %{transaction_summary: tx_summary}
       ) do
    Logger.warning("Invalid transaction #{inspect(reason)}")
    # notify welcome node
    message = %Error{address: tx_summary.address, reason: reason}

    Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
      P2P.send_message(
        Crypto.last_node_public_key(),
        message
      )

      :ok
    end)

    :error
  end

  defp reduce_confirmations(_, :error), do: :error

  defp notify(:error), do: :skip

  defp notify(%{
         confirmations: [],
         transaction_summary: %TransactionSummary{address: tx_address, type: tx_type}
       }) do
    # notify welcome node
    message = %Error{address: tx_address, reason: :network_issue}

    Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
      P2P.send_message(
        Crypto.last_node_public_key(),
        message
      )

      :ok
    end)

    Logger.error("Not confirmations for the transaction",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )
  end

  defp notify(%{
         confirmations: confirmations,
         transaction_summary: tx_summary,
         context: context
       }) do
    notify_attestation(confirmations, tx_summary, context)
    notify_io_nodes(context)
  end

  defp notify_attestation(
         confirmations,
         tx_summary,
         context = %ValidationContext{}
       ) do
    welcome_node = P2P.get_node_info()

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
        do: %ReplicateTransactionChain{transaction: validated_tx},
        else: %ReplicateTransaction{transaction: validated_tx}
    )
  end
end
