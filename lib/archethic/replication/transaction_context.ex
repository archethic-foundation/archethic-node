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
        do_fetch_transaction_chain(nodes, address)
    end
  end

  defp do_fetch_transaction_chain(nodes, address, prev_result \\ nil)

  defp do_fetch_transaction_chain([node | rest], address, _prev_result) do
    case P2P.send_message(node, %GetTransactionChain{address: address}) do
      {:ok, %TransactionList{transactions: []}} ->
        do_fetch_transaction_chain(rest, address, [])

      {:ok, %TransactionList{transactions: transactions}} ->
        transactions

      {:error, _} ->
        do_fetch_transaction_chain(rest, address)
    end
  end

  defp do_fetch_transaction_chain([], _address, nil), do: raise("Cannot fetch transaction chain")
  defp do_fetch_transaction_chain([], _address, prev_result), do: prev_result

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
        do_fetch_unspent_outputs(nodes, address)
    end
  end

  defp do_fetch_unspent_outputs(nodes, address, prev_result \\ nil)

  defp do_fetch_unspent_outputs([node | rest], address, _prev_result) do
    case P2P.send_message(node, %GetUnspentOutputs{address: address}) do
      {:ok, %UnspentOutputList{unspent_outputs: []}} ->
        do_fetch_unspent_outputs(rest, address, [])

      {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} ->
        unspent_outputs

      {:error, _} ->
        do_fetch_unspent_outputs(rest, address)
    end
  end

  defp do_fetch_unspent_outputs([], _, nil), do: raise("Cannot fetch unspent outputs")
  defp do_fetch_unspent_outputs([], _, prev_result), do: prev_result

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
        nodes
        |> do_fetch_inputs(address)
        |> Enum.filter(&(DateTime.diff(&1.timestamp, timestamp) <= 0))
    end
  end

  defp do_fetch_inputs(nodes, address, prev_result \\ nil)

  defp do_fetch_inputs([node | rest], address, _prev_result) do
    case P2P.send_message(node, %GetTransactionInputs{address: address}) do
      {:ok, %TransactionInputList{inputs: []}} ->
        do_fetch_inputs(rest, address, [])

      {:ok, %TransactionInputList{inputs: inputs}} ->
        inputs

      {:error, _} ->
        do_fetch_inputs(rest, address)
    end
  end

  defp do_fetch_inputs([], _, nil), do: raise("Cannot fetch inputs")
  defp do_fetch_inputs([], _, prev_result), do: prev_result

  defp replication_nodes(address, _timestamp, _) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> P2P.unprioritize_node(Crypto.first_node_public_key())
  end
end
