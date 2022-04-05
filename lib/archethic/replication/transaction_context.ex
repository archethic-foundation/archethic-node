defmodule ArchEthic.Replication.TransactionContext do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetTransactionInputs
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

  require Logger

  @doc """
  Fetch transaction
  """
  @spec fetch_transaction(address :: Crypto.versioned_hash()) :: Transaction.t() | nil
  def fetch_transaction(address) when is_binary(address) do
    case replication_nodes(address) do
      [] ->
        nil

      nodes ->
        fetch_transaction(nodes, address)
    end
  end

  defp fetch_transaction(
         _nodes = [node | rest],
         address
       ) do
    message = %GetTransaction{
      address: address
    }

    case P2P.send_message(node, message) do
      {:ok, tx = %Transaction{}} ->
        tx

      {:ok, %NotFound{}} ->
        nil

      {:error, _} ->
        fetch_transaction(rest, address)
    end
  end

  defp fetch_transaction([], _address),
    do: raise("Cannot fetch transaction chain")

  @doc """
  Stream transaction chain
  """
  @spec stream_transaction_chain(address :: Crypto.versioned_hash()) :: Enumerable.t() | list(Transaction.t())
  def stream_transaction_chain(address) when is_binary(address) do
    case replication_nodes(address) do
      [] ->
        []

      nodes ->
        Stream.resource(
          fn -> {address, nil, 0} end,
          fn
            {:end, size} ->
              Logger.debug("Size of the chain retrieved: #{size}",
                transaction_address: Base.encode16(address)
              )

              {:halt, address}

            {address, paging_state, size} ->
              case fetch_transaction_chain(nodes, address, paging_state) do
                {transactions, false, _} ->
                  {[transactions], {:end, size + length(transactions)}}

                {transactions, true, paging_state} ->
                  {[transactions], {address, paging_state, size + length(transactions)}}
              end
          end,
          fn _ -> :ok end
        )
    end
  end

  defp fetch_transaction_chain(
         _nodes = [node | rest],
         address,
         paging_state
       ) do
    message = %GetTransactionChain{
      address: address,
      paging_state: paging_state
    }

    case P2P.send_message(node, message) do
      {:ok,
       %TransactionList{transactions: transactions, more?: more?, paging_state: paging_state}} ->
        {transactions, more?, paging_state}

      {:error, _} ->
        fetch_transaction_chain(rest, address, paging_state)
    end
  end

  defp fetch_transaction_chain([], _address, _paging_state),
    do: raise("Cannot fetch transaction chain")

  @doc """
  Fetch the transaction unspent outputs
  """
  @spec fetch_unspent_outputs(address :: Crypto.versioned_hash()) ::
          list(UnspentOutput.t())
  def fetch_unspent_outputs(address) when is_binary(address) do
    case replication_nodes(address) do
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
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), DateTime.t()) ::
          list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{}) when is_binary(address) do
    case replication_nodes(address) do
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

  defp replication_nodes(address) do
    address
    # returns the storage nodes for the transaction chain based on the transaction address
    # from a list of available node
    |> Election.chain_storage_nodes(P2P.available_nodes())
    #  Returns the nearest storages nodes from the local node as per the patch
    #  when the input is a list of nodes
    |> P2P.nearest_nodes()
    # Determine if the node is locally available based on its availability history.
    # If the last exchange with node was succeed the node is considered as available
    |> Enum.filter(&Node.locally_available?/1)
    # Reorder a list of nodes to ensure the current node is only called at the end
    |> P2P.unprioritize_node(Crypto.first_node_public_key())
  end
end
