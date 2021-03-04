defmodule Uniris.Mining.StandaloneWorkflow do
  @moduledoc """
  Transaction validation is performed in a single node processing.
  This workflow should be executed only when the network is bootstrapping (only 1 validation node)

  The single node will auto validate the transaction
  """
  use Task

  alias Uniris.Crypto

  alias Uniris.Mining.TransactionContext
  alias Uniris.Mining.ValidationContext

  alias Uniris.P2P
  alias Uniris.P2P.Message.ReplicateTransaction

  alias Uniris.Replication

  alias Uniris.TransactionChain.Transaction

  require Logger

  def start_link(opts \\ []) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(opts) do
    tx = Keyword.get(opts, :transaction)
    Logger.info("Start mining", transaction: Base.encode16(tx.address))

    chain_storage_nodes =
      Replication.chain_storage_nodes(tx.address, tx.type, P2P.list_nodes(availability: :global))

    beacon_storage_nodes = Replication.beacon_storage_nodes(tx.address, tx.timestamp)

    {prev_tx, unspent_outputs, previous_storage_nodes, chain_storage_nodes_view,
     beacon_storage_nodes_view,
     validation_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        Enum.map(chain_storage_nodes, & &1.last_public_key),
        Enum.map(beacon_storage_nodes, & &1.last_public_key),
        [Crypto.node_public_key()]
      )

    ValidationContext.new(
      transaction: tx,
      welcome_node: P2P.get_node_info(),
      validation_nodes: [P2P.get_node_info()],
      chain_storage_nodes: chain_storage_nodes,
      beacon_storage_nodes: beacon_storage_nodes
    )
    |> ValidationContext.put_transaction_context(
      prev_tx,
      unspent_outputs,
      previous_storage_nodes,
      chain_storage_nodes_view,
      beacon_storage_nodes_view,
      validation_nodes_view
    )
    |> validate()
    |> replicate()
  end

  defp validate(context = %ValidationContext{}) do
    context
    |> ValidationContext.create_validation_stamp()
    |> ValidationContext.cross_validate()
  end

  defp replicate(context) do
    validated_tx = ValidationContext.get_validated_transaction(context)

    context
    |> ValidationContext.get_storage_nodes()
    |> P2P.broadcast_message(%ReplicateTransaction{transaction: validated_tx})
  end
end
