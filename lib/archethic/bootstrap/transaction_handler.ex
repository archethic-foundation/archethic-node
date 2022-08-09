defmodule Archethic.Bootstrap.TransactionHandler do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.NewTransaction
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), list(Node.t())) :: :ok | {:error, :network_issue}
  def send_transaction(tx = %Transaction{address: address}, nodes) do
    Logger.info("Send node transaction...",
      transaction_address: Base.encode16(address),
      transaction_type: "node"
    )

    do_send_transaction(nodes, tx)
  end

  defp do_send_transaction([node | rest], tx) do
    case P2P.send_message(node, %NewTransaction{transaction: tx}) do
      {:ok, %Ok{}} ->
        Logger.info("Waiting transaction validation",
          transaction_address: Base.encode16(tx.address),
          transaction_type: "node"
        )

        storage_nodes =
          Election.chain_storage_nodes_with_type(tx.address, tx.type, P2P.available_nodes())

        await_confirmation(tx.address, storage_nodes)

        :ok

      {:error, _} = e ->
        Logger.error("Cannot send node transaction - #{inspect(e)}",
          node: Base.encode16(node.first_public_key)
        )

        do_send_transaction(rest, tx)
    end
  end

  defp do_send_transaction([], _), do: {:error, :network_issue}

  defp await_confirmation(tx_address, [node | rest]) do
    case P2P.send_message(node, %GetTransactionSummary{address: tx_address}) do
      {:ok, %TransactionSummary{address: ^tx_address}} ->
        :ok

      {:ok, %NotFound{}} ->
        Process.sleep(200)
        await_confirmation(tx_address, [node | rest])

      {:error, e} ->
        Logger.error("Cannot get transaction summary - #{inspect(e)}",
          node: Base.encode16(node.first_public_key)
        )

        await_confirmation(tx_address, rest)
    end
  end

  @doc """
  Create a new node transaction
  """
  @spec create_node_transaction(
          ip_address :: :inet.ip_address(),
          p2p_port :: :inet.port_number(),
          http_port :: :inet.port_number(),
          transport :: P2P.supported_transport(),
          reward_address :: Crypto.versioned_hash()
        ) ::
          Transaction.t()
  def create_node_transaction(ip = {_, _, _, _}, port, http_port, transport, reward_address)
      when is_number(port) and port >= 0 and is_binary(reward_address) do
    origin_public_key = Crypto.origin_node_public_key()
    origin_public_key_certificate = Crypto.get_key_certificate(origin_public_key)

    Transaction.new(:node, %TransactionData{
      code: """
        condition inherit: [
          # We need to ensure the type stays consistent
          type: :node,
          content: true
        ]
      """,
      content:
        Node.encode_transaction_content(
          ip,
          port,
          http_port,
          transport,
          reward_address,
          origin_public_key,
          origin_public_key_certificate
        )
    })
  end
end
