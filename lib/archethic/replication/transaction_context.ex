defmodule ArchEthic.Replication.TransactionContext do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetTransactionInputs
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

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

  defp replication_nodes(address, _timestamp, _) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> P2P.unprioritize_node(Crypto.first_node_public_key())
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
