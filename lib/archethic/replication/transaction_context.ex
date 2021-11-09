defmodule ArchEthic.Replication.TransactionContext do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetTransactionInputs
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

  alias ArchEthic.Replication

  @doc """
  Fetch transaction chain
  """
  @spec fetch_transaction_chain(
          address :: Crypto.versioned_hash(),
          timestamp :: DateTime.t(),
          force_remote_download? :: boolean()
        ) :: list(Transaction.t())
  def fetch_transaction_chain(address, timestamp = %DateTime{}, force_remote_download? \\ false)
      when is_binary(address) and is_boolean(force_remote_download?) do
    case replication_nodes(address, timestamp, force_remote_download?) do
      [] ->
        []

      nodes ->
        %TransactionList{transactions: txs} =
          reply_first(nodes, %GetTransactionChain{address: address})

        txs
    end
  end

  @doc """
  Fetch the transaction unspent outputs
  """
  @spec fetch_unspent_outputs(address :: Crypto.versioned_hash(), timestamp :: DateTime.t()) ::
          list(UnspentOutput.t())
  def fetch_unspent_outputs(address, timestamp) when is_binary(address) do
    case replication_nodes(address, timestamp, false) do
      [] ->
        []

      nodes ->
        %UnspentOutputList{unspent_outputs: utxos} =
          reply_first(nodes, %GetUnspentOutputs{address: address})

        utxos
    end
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time
  """
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), timestamp :: DateTime.t()) ::
          list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{}) when is_binary(address) do
    case replication_nodes(address, timestamp, false) do
      [] ->
        []

      nodes ->
        %TransactionInputList{inputs: inputs} =
          reply_first(nodes, %GetTransactionInputs{address: address})

        Enum.filter(inputs, &(DateTime.diff(&1.timestamp, timestamp) <= 0))
    end
  end

  defp replication_nodes(address, timestamp, true) do
    address
    |> Replication.chain_storage_nodes()
    |> Enum.filter(&(DateTime.compare(&1.authorization_date, timestamp) == :lt))
    |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))
  end

  defp replication_nodes(address, timestamp, false) do
    address
    |> Replication.chain_storage_nodes()
    |> Enum.filter(&(DateTime.compare(&1.authorization_date, timestamp) == :lt))
  end

  defp reply_first([node | rest], message) do
    case P2P.send_message(node, message) do
      {:ok, data} ->
        data

      {:error, _} ->
        reply_first(rest, message)
    end
  end
end
