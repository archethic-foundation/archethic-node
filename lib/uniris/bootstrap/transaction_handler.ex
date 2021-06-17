defmodule Uniris.Bootstrap.TransactionHandler do
  @moduledoc false

  use Retry

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.Error
  alias Uniris.P2P.Message.NewTransaction
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), list(Node.t())) :: :ok | {:error, :network_issue}
  def send_transaction(tx = %Transaction{address: address}, nodes) do
    Logger.info("Send node transaction...", transaction: "node@#{Base.encode16(address)}")
    Logger.info("Waiting transaction replication", transaction: "node@#{Base.encode16(address)}")

    case P2P.reply_first(nodes, %NewTransaction{transaction: tx}) do
      {:ok, %Ok{}} ->
        :ok

      {:ok, %Error{reason: :network_issue}} ->
        {:error, :network_issue}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Create a new node transaction
  """
  @spec create_node_transaction(
          :inet.ip_address(),
          :inet.port_number(),
          Transport.supported(),
          Crypto.versioned_hash()
        ) ::
          Transaction.t()
  def create_node_transaction(ip = {_, _, _, _}, port, transport, reward_address)
      when is_number(port) and port >= 0 and is_binary(reward_address) do
    key_certificate = Crypto.get_key_certificate(Crypto.last_node_public_key())

    Transaction.new(:node, %TransactionData{
      content:
        Node.encode_transaction_content(ip, port, transport, reward_address, key_certificate)
    })
  end
end
