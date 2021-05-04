defmodule Uniris.Replication.TransactionContext do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.TransactionChain.TransactionInput

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Uniris.Replication

  @doc """
  Fetch transaction chain
  """
  @spec fetch_transaction_chain(
          address :: Crypto.versioned_hash(),
          timestamp :: DateTime.t(),
          force_remote_download? :: boolean()
        ) ::
          Enumerable.t() | list(Transaction.t())
  def fetch_transaction_chain(address, timestamp = %DateTime{}, force_remote_download? \\ false)
      when is_binary(address) and is_boolean(force_remote_download?) do
    message = %GetTransactionChain{address: address}

    do_fetch(
      address,
      message,
      fn
        {:ok, %TransactionList{transactions: transactions}} -> transactions
        _ -> []
      end,
      timestamp,
      force_remote_download?
    )
  end

  @doc """
  Fetch the transaction unspent outputs
  """
  @spec fetch_unspent_outputs(address :: Crypto.versioned_hash(), timestamp :: DateTime.t()) ::
          Enumerable.t() | list(UnspentOutput.t())
  def fetch_unspent_outputs(address, timestamp) when is_binary(address) do
    message = %GetUnspentOutputs{address: address}

    do_fetch(
      address,
      message,
      fn
        {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} ->
          unspent_outputs

        _ ->
          []
      end,
      timestamp
    )
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time
  """
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), timestamp :: DateTime.t()) ::
          Enumerable.t() | list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{}) when is_binary(address) do
    message = %GetTransactionInputs{address: address}

    do_fetch(
      address,
      message,
      fn
        {:ok, %TransactionInputList{inputs: inputs}} ->
          Enum.filter(inputs, &DateTime.diff(&1.timestamp, timestamp) <= 0)

        _ ->
          []
      end,
      timestamp
    )
  end

  defp do_fetch(address, message, result_handler, timestamp, force_remote_download? \\ false) do
    case replication_nodes(address, timestamp, force_remote_download?) do
      [] ->
        result_handler.({:error, :not_found})

      nodes ->
        nodes
        |> P2P.reply_first(message)
        |> result_handler.()
    end
  end

  defp replication_nodes(address, timestamp, true) do
    address
    |> Replication.chain_storage_nodes()
    |> Enum.filter(&(DateTime.compare(&1.authorization_date, timestamp) == :lt))
    |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
  end

  defp replication_nodes(address, timestamp, false) do
    address
    |> Replication.chain_storage_nodes()
    |> Enum.filter(&(DateTime.compare(&1.authorization_date, timestamp) == :lt))
  end
end
