defmodule UnirisCore.Mining.Context do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Election
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.TaskSupervisor
  alias UnirisCore.Storage
  alias UnirisCore.Crypto

  require Logger

  @spec fetch(Transaction.pending(), with_confirmation :: boolean()) ::
          {previous_chain :: list(Transaction.validated()),
           unspent_outputs :: list(Transaction.validated()), involved_nodes :: list(Node.t())}
  def fetch(tx, with_confirmation \\ false)

  def fetch(%Transaction{type: :node, previous_public_key: previous_public_key}, _) do
    do_fetch_network_transaction_chain(previous_public_key)
  end

  def fetch(%Transaction{type: :node_shared_secrets, previous_public_key: previous_public_key}, _) do
    do_fetch_network_transaction_chain(previous_public_key)
  end

  def fetch(%Transaction{previous_public_key: previous_public_key}, with_confirmation) do
    previous_address = Crypto.hash(previous_public_key)
    previous_storage_nodes = closest_storage_nodes(previous_address)

    # Retrieve previous transaction context by querying the network about the previous transaction chain,
    # received unspent outputs and involve the storages nodes which replied.
    {:ok, previous_chain, unspent_outputs, involved_storage_node} =
      download(previous_address, previous_storage_nodes)

    if with_confirmation do
      {:ok, previous_chain, unspent_outputs, involved_confirmation_nodes} =
        confirm(
          previous_chain,
          unspent_outputs,
          previous_storage_nodes -- [involved_storage_node]
        )

      involved_nodes =
        [involved_storage_node | involved_confirmation_nodes]
        |> Enum.filter(& &1)
        |> Enum.uniq()

      {previous_chain, unspent_outputs, involved_nodes}
    else
      {previous_chain, unspent_outputs, Enum.filter([involved_storage_node], & &1)}
    end
  end

  defp do_fetch_network_transaction_chain(previous_public_key) do
    previous_address = Crypto.hash(previous_public_key)
    case Storage.get_transaction_chain(previous_address) do
      {:error, :transaction_chain_not_exists} ->
        {[], [], []}
      {:ok, chain} ->
        {chain, [], [Crypto.node_public_key()]}
    end
  end

  @doc """
  Return the closest storage nodes for a given transaction address
  """
  @spec closest_storage_nodes(address :: binary()) :: closest_nodes :: list(Node.t())
  def closest_storage_nodes(tx_address) do
    %Node{network_patch: patch} = P2P.node_info()

    tx_address
    |> Election.storage_nodes()
    |> P2P.nearest_nodes(patch)
    |> Enum.map(& &1.last_public_key)
  end

  @doc """
  Download the previous chain and the unspent outputs for the given transaction.

  A list of closest is iterated recursively if some network issue happens, so the next closest node will be picked.

  Returns also the node used to retrieve the data to reward it.
  """
  @spec download(address :: binary(), storage_nodes :: list(Node.t())) ::
          {:ok, previous_chain :: list(Transaction.validated()),
           unspent_outputs :: list(Transaction.validated()), involved_node :: Node.t()}
          | {:error, :network_issue}
  def download(_, []), do: {:ok, [], [], nil}

  def download(
        tx_address,
        [closest_storage_node | rest]
      ) do
    message = [{:get_transaction_chain, tx_address}, {:get_unspent_outputs, tx_address}]

    closest_storage_node
    |> P2P.send_message(message)
    |> case do
      [{:ok, chain}, {:ok, unspent_outputs}] ->
        {:ok, chain, unspent_outputs, closest_storage_node}

      [{:ok, chain}, {:error, :unspent_output_transactions_not_exists}] ->
        {:ok, chain, [], closest_storage_node}

      [{:error, :transaction_chain_not_exists}, {:ok, unspent_outputs}] ->
        {:ok, [], unspent_outputs, closest_storage_node}

      [{:error, :transaction_chain_not_exists}, {:error, :unspent_output_transactions_not_exists}] ->
        {:ok, [], [], nil}

      _ ->
        download(tx_address, rest)
    end
  end

  @doc """
  Provide an acknowledgement for the context retrieved by requesting others nodes if chain or unspent outputs exists.

  For the previous transaction chain, the proof of integrity of the previous transaction chain is requested to verify
  its integrity.

  For unspent outputs, acknowledgements on the respective origin storage pool is requested to
  confirm the validity of the transaction

  In any cases, the additional involved nodes are added to the list of storage nodes to reward.
  """
  @spec confirm(
          list(Transaction.validated()),
          list(Transaction.validated()),
          list(Node.t())
        ) ::
          {:ok, list(Transaction.validated()), list(Transaction.validated()), list(Node.t())}
  def confirm([], [], nil, _), do: {:ok, [], [], []}

  def confirm([], unspent_outputs, _) when is_list(unspent_outputs) do
    # Request to confirm the unspent ouutputs transactions
    %{utxo: confirmed_unspent_outputs, nodes: utxo_storage_nodes} =
      unspent_outputs
      |> confirm_unspent_outputs
      |> reduce_unspent_outputs_confirmation

    {:ok, [], confirmed_unspent_outputs, utxo_storage_nodes}
  end

  def confirm(chain = [last_tx | _], unspent_outputs, previous_storage_nodes)
      when is_list(unspent_outputs) and is_list(previous_storage_nodes) do
    # Request to confirm the transaction chain integrity retrieved
    t1 =
      Task.Supervisor.async(
        TaskSupervisor,
        fn -> confirm_chain_integrity(last_tx, previous_storage_nodes) end
      )

    # Request to confirm the unspent outputs transactions
    t2 = Task.Supervisor.async(TaskSupervisor, fn -> confirm_unspent_outputs(unspent_outputs) end)

    with {:ok, confirm_previous_storage_node} <- Task.await(t1),
         confirmed_unspent_outputs <- Task.await(t2) do
      %{utxo: unspent_outputs, nodes: utxo_storage_nodes} =
        reduce_unspent_outputs_confirmation(confirmed_unspent_outputs)

      {:ok, chain, unspent_outputs, [confirm_previous_storage_node | utxo_storage_nodes]}
    end
  end

  defp reduce_unspent_outputs_confirmation(confirmed_unspent_outputs) do
    Enum.reduce(confirmed_unspent_outputs, %{utxo: [], nodes: []}, fn {utxo, node}, acc ->
      acc
      |> Map.update!(:utxo, &(&1 ++ [utxo]))
      |> Map.update!(:nodes, &(&1 ++ [node]))
    end)
  end

  defp confirm_chain_integrity(
         tx = %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{proof_of_integrity: poi}
         },
         [storage_node | rest]
       ) do
    case P2P.send_message(storage_node, {:get_proof_of_integrity, tx_address}) do
      {:ok, proof_of_integrity} when poi == proof_of_integrity ->
        {:ok, storage_node}

      {:ok, _} ->
        {:error, :invalid_transaction_chain}

      _ ->
        confirm_chain_integrity(tx, rest)
    end
  end

  defp confirm_chain_integrity(_, []) do
    Logger.error("Network issue to confirm chain integrity")
    {:error, :network_issue}
  end

  defp confirm_unspent_outputs(unspent_outputs) do
    Task.Supervisor.async_stream_nolink(TaskSupervisor, unspent_outputs, fn utxo ->
      closest_nodes = closest_storage_nodes(utxo.address)
      confirm_unspent_output(utxo, closest_nodes)
    end)
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.filter(fn res -> match?({:ok, _, _}, res) end)
    |> Enum.map(fn {:ok, utxo, node} -> {utxo, node} end)
  end

  defp confirm_unspent_output(unspent_output = %Transaction{}, [closest_node | rest]) do
    case P2P.send_message(closest_node, {:get_transaction, unspent_output.address}) do
      {:ok, tx} when tx == unspent_output ->
        {:ok, tx, closest_node}

      {:ok, _} ->
        {:error, :invalid_unspent_output}

      {:error, :network_issue} ->
        confirm_unspent_output(unspent_output, rest)
    end
  end

  defp confirm_unspent_output(_, []) do
    Logger.error("Network issue to confirm unspent output")
    {:error, :network_issue}
  end
end
