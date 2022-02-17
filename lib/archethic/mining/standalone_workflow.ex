defmodule ArchEthic.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use Task

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.ReplicationAttestation

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.Mining.PendingTransactionValidation
  alias ArchEthic.Mining.TransactionContext
  alias ArchEthic.Mining.ValidationContext

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.AcknowledgeStorage
  alias ArchEthic.P2P.Message.Error
  alias ArchEthic.P2P.Message.ReplicateTransaction
  alias ArchEthic.P2P.Message.ReplicateTransactionChain
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionSummary

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

    chain_storage_nodes =
      Election.chain_storage_nodes_with_type(
        tx.address,
        tx.type,
        P2P.available_nodes()
      )

    beacon_storage_nodes =
      Election.beacon_storage_nodes(
        BeaconChain.subset_from_address(tx.address),
        BeaconChain.next_slot(DateTime.utc_now()),
        P2P.authorized_nodes()
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
      beacon_storage_nodes: beacon_storage_nodes
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
      "Send validated transaction to #{Enum.map_join(chain_storage_nodes, ",", &"#{Node.endpoint(&1)}")}",
      transaction_address: Base.encode16(validated_tx.address),
      transaction_type: validated_tx.type
    )

    Task.async_stream(
      chain_storage_nodes,
      fn node ->
        {P2P.send_message!(node, %ReplicateTransactionChain{
           transaction: validated_tx,
           ack_storage?: true
         }), node}
      end,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, res} -> res end)
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
          }, %Node{last_public_key: node_public_key}},
         acc = %{transaction_summary: tx_summary, context: context}
       ) do
    if Crypto.verify?(signature, TransactionSummary.serialize(tx_summary), node_public_key) do
      {:ok, position} = ValidationContext.get_chain_storage_position(context, node_public_key)
      Map.update!(acc, :confirmations, &[{position, signature} | &1])
    else
      acc
    end
  end

  defp reduce_confirmations({%Error{}, _}, _acc), do: raise("Invalid transaction")

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

    P2P.broadcast_message(
      P2P.distinct_nodes([welcome_node | beacon_storage_nodes]),
      attestation
    )
  end

  defp notify_io_nodes(%ValidationContext{
         io_storage_nodes: io_storage_nodes,
         transaction: tx,
         chain_storage_nodes: chain_storage_nodes
       }) do
    (io_storage_nodes -- chain_storage_nodes)
    |> P2P.broadcast_message(%ReplicateTransaction{transaction: tx})
  end
end
