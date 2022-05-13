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

    chain_storage_nodes =
      Election.chain_storage_nodes_with_type(
        tx.address,
        tx.type,
        [P2P.get_node_info()]
      )

    beacon_storage_nodes =
      Election.beacon_storage_nodes(
        BeaconChain.subset_from_address(tx.address),
        BeaconChain.next_slot(DateTime.utc_now()),
        [P2P.get_node_info()]
      )

    {prev_tx, unspent_outputs, previous_storage_nodes, chain_storage_nodes_view,
     beacon_storage_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        Enum.map(chain_storage_nodes, & &1.last_public_key),
        Enum.map(beacon_storage_nodes, & &1.last_public_key)
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
      welcome_node: P2P.get_node_info(),
      validation_nodes: [P2P.get_node_info()],
      chain_storage_nodes: chain_storage_nodes,
      beacon_storage_nodes: beacon_storage_nodes,
      validation_time: validation_time
    )
    |> ValidationContext.set_pending_transaction_validation(valid_pending_transaction?)
    |> ValidationContext.put_transaction_context(
      prev_tx,
      unspent_outputs,
      previous_storage_nodes,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
    |> validate()
    |> replicate_and_aggregate_confirmations()
    |> notify()
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.confirm_validation_node(Crypto.last_node_public_key())
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.cross_validate()
  end

  defp replicate_and_aggregate_confirmations(
         context = %ValidationContext{chain_storage_nodes: chain_storage_nodes}
       ) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    Logger.info(
      "Send transaction to storage nodes: #{Enum.map_join(chain_storage_nodes, ",", &Node.endpoint/1)}",
      transaction_address: Base.encode16(validated_tx.address),
      transaction_type: validated_tx.type
    )

    Task.async_stream(
      chain_storage_nodes,
      fn node ->
        {P2P.send_message(node, %ReplicateTransactionChain{
           transaction: validated_tx,
           ack_storage?: true
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

  defp reduce_confirmations({%Error{reason: reason}, _}, _acc) do
    Logger.warning("Invalid transaction #{inspect(reason)}")
    :error
  end

  defp reduce_confirmations(_, :error), do: :error

  defp notify(:error), do: :skip

  defp notify(%{
         confirmations: [],
         transaction_summary: %TransactionSummary{address: tx_address, type: tx_type}
       }) do
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
         %ValidationContext{beacon_storage_nodes: beacon_storage_nodes}
       ) do
    welcome_node = P2P.get_node_info()

    attestation = %ReplicationAttestation{
      transaction_summary: tx_summary,
      confirmations: confirmations
    }

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
           io_storage_nodes: io_storage_nodes,
           chain_storage_nodes: chain_storage_nodes
         }
       ) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    (io_storage_nodes -- chain_storage_nodes)
    |> tap(fn nodes ->
      Logger.debug(
        "Send transaction to IO nodes: #{Enum.map_join(nodes, ",", &Node.endpoint/1)}",
        transaction_address: Base.encode16(validated_tx.address),
        transaction_type: validated_tx.type
      )
    end)
    |> P2P.broadcast_message(%ReplicateTransaction{transaction: validated_tx})
  end
end
