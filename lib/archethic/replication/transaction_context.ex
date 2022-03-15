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
        # if the selected node from rest dont have the txn list / node is unavailable
        #   then try to fetch frpm rest of  other nodes
        do_fetch_transaction_chain(rest, address, [])

      {:ok, %TransactionList{transactions: transactions}} ->
        transactions

      {:error, _} ->
        # if fetching from current node return error then chosee from the rest of the nodes
        do_fetch_transaction_chain(rest, address)
    end
  end

  defp do_fetch_transaction_chain([], _address, nil), do: raise("Cannot fetch transaction chain")
  defp do_fetch_transaction_chain([], _address, prev_result), do: prev_result

  # ===========================================================================================

  @doc """
  Finds the closest node and starts the process of replication of complete TXNCHAIN if exists
  """
  def fetch_complete_transaction_chain(
        address,
        timestamp = %DateTime{},
        force_remote_download? \\ false
      )
      when is_binary(address) and is_boolean(force_remote_download?) do
    case replication_nodes(address, timestamp, force_remote_download?) do
      [] ->
        []

      nodes ->
        # returns {:ok , []} else returns error
        replicate_transaction_chain(nodes, address, timestamp, nil ,[])
    end
  end




  defp replicate_transaction_chain(
         [node | rest],
         address,
         time_after = %DateTime{},
         page_state \\ nil,
         _prev_result \\ nil
       ) do
    case P2P.send_message(node, %GetTransactionChain{
           address: address,
           after: time_after,
           page: page_state
         }) do
        # ------------------------------------------------------------------
      #  case 0: erraneou cases
      {:ok, %TransactionList{transactions: [], more?: _, page:  nil}} ->
        replicate_transaction_chain(rest, address, time_after, nil, [])

      # ------------------------------------------------------------------
      #  case 1: if  txn_chain have many transactions and more than one page of data and more page  is pending
      #  then process transactions and request for next page data from same node against same time after
      #  if any error look for same data and time_after from another nodes
      {:ok, %TransactionList{transactions: transactions, more?: true, page: page}}  ->
        case process_transactions(transactions, address, time_after, page) do
          {:ok, _new_time_after} ->
            replicate_transaction_chain([node | rest], address, time_after, page, [])

          {:error, _} ->
            replicate_transaction_chain(rest, address, time_after, nil, [])
        end

      # ------------------------------------------------------------------
      #  case 2: if txn_chain have many transactions and more than one page of data and NO more page is pending
      #  then process transactions and get new_time_after from last transaction.
      #  then fetch for more Txn chain against same address and new_time_after from last_transaction
      #  from the remaining nodes, with page state nil.if error proceed with rest of nodes
      {:ok, %TransactionList{transactions: transactions, more?: false, page: page}} ->
        case process_transactions(transactions, address, time_after, page) do
          {:ok, new_time_after} ->
            replicate_transaction_chain(rest, address, new_time_after, nil, [])

          {:error, _} ->
            replicate_transaction_chain(rest, address, time_after, nil, [])
        end


    end
  end

   # return error if we cant fetch the transactions w.r.t address
   defp replicate_transaction_chain([], _address, _time_after, _page_state, nil), do: {:error, []}

   # determines end of recusion by marking empty nodes list and return {:ok , []}
   defp replicate_transaction_chain([], _address, _time_after, _page_state, prev_result),
     do: {:ok, prev_result}

  defp process_transactions(_transactions, _address, time_after, _page) do
    # case write_to_db(transactions,address,page)// includes validate.veridfytxndo
    #   {:ok,new_time_after} -> {:ok,new_time_after}
    #   {:error,_} ->        {:error, time_after}
    #   {_,_} ->        {:error, time_after}
    {:ok, time_after}
  end

  # # ------------------------------------------------------------------
  # #  case 1: if  txn_chain : not available for that node
  # #  then try to fetch from rest of the nodes
  # {:ok, %TransactionList{transactions: [] , more?: false , page: nil}} ->
  #               replicate_transaction_chain(rest, address, time_after, nil, prev_result)

  # # ------------------------------------------------------------------
  # #  case 2: if  node: not available | node: cant establish communications
  # #  then try to fetch from rest of the nodes
  # {:error, _} ->
  #   replicate_transaction_chain(rest , address , time_after, nil, prev_result)
  # # ------------------------------------------------------------------
  # #  case 3: if  txn_chain : Have only 10 transactions or one page of data ,page-no. 0
  # #  then validate.verify.write_txn to db then wait for latest time_after
  # #  if any error it will look for same data corresponing to same time_after
  # #  if sucess :ok  means he fetch more txn w.r.t same address and the new_time_after
  # {:ok, %TransactionList{transactions: transactions ,more?: false , page: 0 }} ->
  #      case process_transactions(transactions, address, time_after , 0) do
  #       {:ok, new_time_after} -> replicate_transaction_chain(rest , address , new_time_after, nil, prev_result)
  #       {:error , _ } ->  replicate_transaction_chain(rest , address , time_after, nil, prev_result)
  #      end

  # ===========================================================================================
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
