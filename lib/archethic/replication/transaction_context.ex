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
        do_fetch_transaction_chain(
          nodes,
          {address, timestamp, _more? = false, _paging_state = nil},
          _acc = []
        )
    end
  end

  # defp do_fetch_transaction_chain(
  #        nodes,
  #        {address, timestamp, more?, paging_state},
  #        prev_result \\ []
  #      )

  defp do_fetch_transaction_chain(
         nodes = [node | rest],
         {address, time_after, more?, paging_state},
         prev_result
       ) do
    message = %GetTransactionChain{address: address, after: time_after, page: paging_state}
    # query all the nodes and keep uniqure txn only ends when no more nodes to query
    # if there are more than two elements in tuple , use maps <- design concepts
    case P2P.send_message(node, message) do
      {:ok, %TransactionList{transactions: [], more?: _more?, page: _paging_state}} ->
        []

      {:ok, %TransactionList{transactions: transactions, more?: true, page: paging_state}} ->
        do_fetch_transaction_chain(
          nodes,
          {address, time_after, true, paging_state},
          List.flatten([transactions | prev_result]) |> Enum.uniq()
        )

      {:ok, %TransactionList{transactions: transactions, more?: false, page: _paging_state}} ->
        List.flatten([transactions | prev_result]) |> Enum.uniq()

      {:error, _} ->
        do_fetch_transaction_chain(rest, {address, time_after, more?, paging_state}, prev_result)
    end
  end

  defp do_fetch_transaction_chain([], {_address, _time_after, _more?, _paging_state}, []),
    do: raise("Cannot fetch transaction chain")

  defp do_fetch_transaction_chain(
         [],
         {_address, _time_after, _more?, _paging_state},
         prev_result
       ),
       do: prev_result

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

    # returns a list of node
  end
end
