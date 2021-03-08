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
  @spec fetch_transaction_chain(address :: Crypto.versioned_hash()) ::
          Enumerable.t() | list(Transaction.t())
  def fetch_transaction_chain(address) when is_binary(address) do
    message = %GetTransactionChain{address: address}

    do_fetch(address, message, fn
      {:ok, %TransactionList{transactions: transactions}} -> transactions
      _ -> []
    end)
  end

  @doc """
  Fetch the transaction unspent outputs
  """
  @spec fetch_unspent_outputs(address :: Crypto.versioned_hash()) ::
          Enumerable.t() | list(UnspentOutput.t())
  def fetch_unspent_outputs(address) when is_binary(address) do
    message = %GetUnspentOutputs{address: address}

    do_fetch(address, message, fn
      {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} ->
        unspent_outputs

      _ ->
        []
    end)
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time
  """
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), timestamp :: DateTime.t()) ::
          Enumerable.t() | list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{}) when is_binary(address) do
    message = %GetTransactionInputs{address: address}

    do_fetch(address, message, fn
      {:ok, %TransactionInputList{inputs: inputs}} ->
        inputs |> Enum.filter(&(&1.timestamp == timestamp))

      _ ->
        []
    end)
  end

  defp do_fetch(address, message, result_handler) do
    address
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
    |> P2P.reply_first(message)
    |> result_handler.()
  end
end
