defmodule Uniris.Bootstrap.TransactionHandler do
  @moduledoc false

  use Retry

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.NewTransaction
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), list(Node.t())) :: :ok | {:error, :network_issue}
  def send_transaction(tx = %Transaction{address: address}, nodes) do
    Logger.info("Send node transaction...", transaction: "node@#{Base.encode16(address)}")

    case P2P.reply_first(nodes, %NewTransaction{transaction: tx}) do
      {:ok, %Ok{}} ->
        Logger.info("Waiting transaction replication",
          transaction: "node@#{Base.encode16(address)}"
        )

        retry_while with:
                      linear_backoff(10, 2)
                      |> cap(1_000)
                      |> Stream.take(10) do
          case P2P.reply_first(nodes, %GetTransaction{address: address}) do
            {:ok,
             %Transaction{
               address: ^address,
               validation_stamp: %ValidationStamp{},
               cross_validation_stamps: [_ | _]
             }} ->
              {:halt, :ok}

            _ ->
              {:cont, {:error, :not_found}}
          end
        end
    end

    :ok
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
    Transaction.new(:node, %TransactionData{
      content: """
      ip: #{:inet_parse.ntoa(ip)}
      port: #{port}
      transport: #{Atom.to_string(transport)}
      reward address: #{reward_address}
      """
    })
  end
end
