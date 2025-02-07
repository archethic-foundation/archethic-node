defmodule Archethic.Bootstrap.TransactionHandler do
  @moduledoc false

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.NewTransaction
  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), list(Node.t())) ::
          {:ok, Transaction.t()} | {:error, :network_issue}
  def send_transaction(tx = %Transaction{address: address}, nodes) do
    Logger.info("Send node transaction...",
      transaction_address: Base.encode16(address),
      transaction_type: "node"
    )

    do_send_transaction(nodes, tx)
  end

  defp do_send_transaction(
         nodes = [node | rest],
         tx = %Transaction{address: address, type: type, data: transaction_data}
       ) do
    case P2P.send_message(node, %NewTransaction{
           transaction: tx,
           welcome_node: node.first_public_key
         }) do
      {:ok, %Ok{}} ->
        Logger.info("Waiting transaction validation",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        case Utils.await_confirmation(address, nodes) do
          {:ok, validated_transaction = %Transaction{address: ^address, data: ^transaction_data}} ->
            {:ok, validated_transaction}

          {:ok, _} ->
            raise("Validated transaction does not correspond to transaction sent")

          {:error, :network_issue} ->
            raise("No node responded with confirmation for new Node tx")
        end

      {:error, _} = e ->
        Logger.error("Cannot send node transaction - #{inspect(e)}",
          node: Base.encode16(node.first_public_key)
        )

        do_send_transaction(rest, tx)
    end
  end

  defp do_send_transaction([], _), do: {:error, :network_issue}

  @doc """
  Create a new node transaction
  """
  @spec create_node_transaction(node_config :: NodeConfig.t()) :: Transaction.t()
  def create_node_transaction(node_config) do
    Transaction.new(:node, %TransactionData{
      code: """
        condition inherit: [
          # We need to ensure the type stays consistent
          type: node,

          # Content and token transfers will be validated during tx's validation
          content: true,
          token_transfers: true
        ]
      """,
      content: Node.encode_transaction_content(node_config)
    })
  end
end
