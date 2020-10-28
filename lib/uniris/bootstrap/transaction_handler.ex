defmodule Uniris.Bootstrap.TransactionHandler do
  @moduledoc false

  alias Uniris.P2P
  alias Uniris.P2P.Message.NewTransaction
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.SubscribeTransactionValidation
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), Node.t()) :: :ok | {:error, :network_issue}
  def send_transaction(tx = %Transaction{}, node = %Node{}) do
    message = %NewTransaction{transaction: tx}
    %Ok{} = P2P.send_message(node, message)
    :ok
  catch
    e ->
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      {:error, :network_issue}
  end

  @doc """
  Create a new node transaction
  """
  @spec create_node_transaction(:inet.ip_address(), :inet.port_number()) :: Transaction.t()
  def create_node_transaction(ip = {_, _, _, _}, port) when is_number(port) and port >= 0 do
    Transaction.new(:node, %TransactionData{
      content: """
      ip: #{:inet_parse.ntoa(ip)}
      port: #{port}
      """
    })
  end

  @doc """
  Await the validation a given transaction address
  """
  @spec await_validation(binary(), Node.t()) :: :ok | {:error, :network_issue}
  def await_validation(address, node = %Node{}) when is_binary(address) do
    message = %SubscribeTransactionValidation{address: address}
    %Ok{} = P2P.send_message(node, message)
    :ok
  end
end
