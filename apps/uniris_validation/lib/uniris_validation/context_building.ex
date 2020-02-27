defmodule UnirisValidation.ContextBuilding do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisCrypto, as: Crypto
  alias UnirisElection, as: Election
  alias UnirisNetwork, as: Network
  alias UnirisValidation.TaskSupervisor

  require Logger

  @spec closest_storage_nodes(binary()) :: list(Node.t())
  def closest_storage_nodes(tx_address) do
    tx_address
    |> Election.storage_nodes(Network.list_nodes(), Network.storage_nonce())
    |> Network.nearest_nodes()
  end

  @doc """
  Download the previous chain and the unspent outputs for the given transaction address.

  A list of closest is iterated recursively if some network issue happens, so the next closest node will be picked.

  Returns also the node used to retrieve the data to reward it.
  """
  @spec download_transaction_context(binary(), list(Node.t())) ::
          {:ok, list(Transaction.validated()), list(Transaction.validated()), Node.t()}
          | {:error, :network_issue}
  def download_transaction_context(
        tx_address,
        [closest_storage_node | rest]
      ) do
    message = [{:get_transaction_chain, tx_address}, {:get_unspent_outputs, tx_address}]

    closest_storage_node
    |> Network.send_message(message)
    |> case do
      {:ok, [{:ok, chain}, {:ok, unspent_outputs}]} ->
        {:ok, chain, unspent_outputs, closest_storage_node}

      {:ok, [{:ok, chain}, {:error, :unspent_outputs_not_exists}]} ->
        {:ok, chain, [], closest_storage_node}

      {:ok, [{:error, :transaction_chain_not_exists}, {:ok, unspent_outputs}]} ->
        {:ok, [], unspent_outputs, closest_storage_node}

      {:ok, [{:error, :transaction_chain_not_exists}, {:error, :unspent_outputs_not_exists}]} ->
        {:ok, [], []}

      _response ->
        download_transaction_context(tx_address, rest)
    end
  end

  def download_transaction_context(_tx_address, []) do
    Logger.error("Network issue to fetch previous data")
    {:error, :network_issue}
  end

  @doc """
  Same as `download_transaction_context/2` but with confirmation about the data retrieval

  For transaction chain retrieval an acknowledgement is requested to the next closest node to confirm the
  proof of integrity received.

  For unspent outputs retrieval, acknowledgements on the respective origin storage pool is requested to
  confirm the validity of the transaction

  In any cases, the additional involved nodes are added to the list of storage nodes to reward.
  """
  @spec with_confirmation(Transaction.pending()) ::
          {:ok, list(Transaction.validated()), list(Transction.validated()), list(Node.t())}
  def with_confirmation(%Transaction{previous_public_key: prev_public_key}) do
    previous_address = Crypto.hash(prev_public_key)
    previous_storage_nodes = closest_storage_nodes(previous_address)

    case download_transaction_context(previous_address, previous_storage_nodes) do
      # Nothing to find, so no rewarded previous storage nodes
      {:ok, [], []} ->
        {:ok, [], [], []}

      {:ok, [], unspent_outputs, prev_storage_node} ->
        # Request to confirm the unspent ouutputs transactions
        %{utxo: confirmed_unspent_outputs, nodes: utxo_storage_nodes} =
          unspent_outputs
          |> confirm_unspent_outputs
          |> reduce_unspent_outputs_confirmation

        {:ok, [], confirmed_unspent_outputs, utxo_storage_nodes ++ [prev_storage_node]}

      {:ok, chain = [last_tx | _], unspent_outputs, prev_storage_node} ->
        # Request to confirm the transaction chain integrity retrieved
        t1 =
          Task.Supervisor.async(TaskSupervisor, fn ->
            # Discard the previously used closest storage node
            # and select new ones to confirm the chain integrity retrieved
            other_previous_storage_nodes = previous_storage_nodes -- [prev_storage_node]
            confirm_chain_integrity(last_tx, other_previous_storage_nodes)
          end)

        # Request to confirm the unspent outputs transactions
        t2 =
          Task.Supervisor.async(TaskSupervisor, fn -> confirm_unspent_outputs(unspent_outputs) end)

        with {:ok, confirm_previous_storage_node} <- Task.await(t1),
             confirmed_unspent_outputs <- Task.await(t2) do
          nodes = [prev_storage_node, confirm_previous_storage_node]

          %{utxo: unspent_outputs, nodes: utxo_storage_nodes} =
            reduce_unspent_outputs_confirmation(confirmed_unspent_outputs)

          {:ok, chain, unspent_outputs, nodes ++ utxo_storage_nodes}
        end
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
         %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{proof_of_integrity: poi}
         },
         [storage_node | rest]
       ) do
    case Network.send_message(storage_node, {:get_proof_of_integrity, tx_address}) do
      {:ok, proof_of_integrity} when poi == proof_of_integrity ->
        {:ok, storage_node}

      {:ok, _} ->
        {:error, :invalid_transaction_chain}

      {:error, :network_issue} ->
        confirm_chain_integrity(tx_address, rest)
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
    case Network.send_message(closest_node, {:get_transaction, unspent_output.address}) do
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
