defmodule UnirisCore.Mining.Context do
  @moduledoc false

  defstruct previous_chain: [],
            unspent_outputs: [],
            involved_nodes: [],
            cross_validation_nodes_view: <<>>,
            chain_storage_nodes_view: [],
            beacon_storage_nodes_view: <<>>

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias UnirisCore.Election
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.TaskSupervisor
  alias UnirisCore.Storage
  alias UnirisCore.Crypto
  alias UnirisCore.Mining.BinarySequence
  alias UnirisCore.P2P.Message.GetTransactionHistory
  alias UnirisCore.P2P.Message.GetProofOfIntegrity
  alias UnirisCore.P2P.Message.GetUnspentOutputs
  alias UnirisCore.P2P.Message.GetTransaction
  alias UnirisCore.P2P.Message.TransactionHistory
  alias UnirisCore.P2P.Message.ProofOfIntegrity
  alias UnirisCore.P2P.Message.UnspentOutputList

  @type t() :: %__MODULE__{
          previous_chain: list(Transaction.t()),
          unspent_outputs: list(UnspentOutput.t()),
          involved_nodes: list(Crypto.key()),
          cross_validation_nodes_view: bitstring(),
          chain_storage_nodes_view: bitstring(),
          beacon_storage_nodes_view: bitstring()
        }

  require Logger

  @doc """
  Compute P2P view for cross validation nodes, chain storage nodes and beacon storage nodes
  """
  @spec compute_p2p_view(
          context :: __MODULE__.t(),
          cross_validation_nodes :: list(Node.t()),
          chain_storage_nodes :: list(Node.t()),
          beacon_storage_nodes :: list(Node.t())
        ) ::
          __MODULE__.t()
  def compute_p2p_view(
        ctx = %__MODULE__{},
        cross_validation_nodes,
        chain_storage_nodes,
        beacon_storage_nodes
      ) do
    %{
      ctx
      | cross_validation_nodes_view: BinarySequence.from_availability(cross_validation_nodes),
        chain_storage_nodes_view: BinarySequence.from_availability(chain_storage_nodes),
        beacon_storage_nodes_view: BinarySequence.from_availability(beacon_storage_nodes)
    }
  end

  @doc """
  Retrieve the history context of a given transaction by fetching the transaction chain and related unspent outputs

  Network transactions chain retrieval happens locally as every node store the chain

  A confirmation is performed to verify the chain integrity and unspent outputs authenticty against other storage nodes.
  """
  @spec fetch_history(__MODULE__.t(), Transaction.pending()) :: __MODULE__.t()

  def fetch_history(ctx = %__MODULE__{}, %Transaction{
        type: :node,
        previous_public_key: previous_public_key
      }) do
    fetch_network_transaction_history(ctx, previous_public_key)
  end

  def fetch_history(ctx = %__MODULE__{}, %Transaction{
        type: :node_shared_secrets,
        previous_public_key: previous_public_key
      }) do
    fetch_network_transaction_history(ctx, previous_public_key)
  end

  def fetch_history(ctx = %__MODULE__{}, %Transaction{previous_public_key: previous_public_key}) do
    previous_address = Crypto.hash(previous_public_key)
    [nearest_node | rest] = closest_storage_nodes(previous_address)

    # Retrieve previous transaction context by querying the network about the previous transaction chain,
    # received unspent outputs and involve the storages nodes which replied.
    %TransactionHistory{
      transaction_chain: chain,
      unspent_outputs: unspent_outputs
    } = P2P.send_message(nearest_node, %GetTransactionHistory{address: previous_address})

    involved_nodes = []

    involved_nodes =
      case chain do
        [] ->
          involved_nodes

        _ ->
          [nearest_node]
      end

    case unspent_outputs do
      [] ->
        involved_nodes

      _ ->
        [nearest_node | involved_nodes]
    end

    %{
      ctx
      | previous_chain: chain,
        unspent_outputs: unspent_outputs,
        involved_nodes: Enum.uniq(involved_nodes)
    }
    |> confirm(rest, previous_address)
  end

  # Performs a lookup into the node database to search the previous chain as every node is storing network transactions
  # Unspent outputs and confirmation will be fetched as other transactions by requesting other nodes
  defp fetch_network_transaction_history(ctx = %__MODULE__{}, previous_public_key) do
    previous_address = Crypto.hash(previous_public_key)

    nearest_node = List.first(closest_storage_nodes(previous_address))

    %UnspentOutputList{unspent_outputs: unspent_outputs} =
      P2P.send_message(nearest_node, %GetUnspentOutputs{address: previous_address})

    previous_chain = Storage.get_transaction_chain(previous_address)

    {:ok, %Node{network_patch: patch}} = P2P.node_info()

    other_chain_storage_nodes =
      P2P.list_nodes()
      |> Enum.filter(& &1.ready?)
      |> Enum.reject(&(&1.last_public_key == Crypto.node_public_key()))
      |> P2P.nearest_nodes(patch)
      |> Enum.map(& &1.last_public_key)

    involved_nodes =
      case previous_chain do
        [] ->
          []

        _ ->
          [Crypto.node_public_key()]
      end

    involved_nodes =
      case unspent_outputs do
        [] ->
          involved_nodes

        _ ->
          [nearest_node | involved_nodes]
      end

    %{
      ctx
      | previous_chain: previous_chain,
        unspent_outputs: unspent_outputs,
        involved_nodes: Enum.uniq(involved_nodes)
    }
    |> confirm(other_chain_storage_nodes, previous_address)
  end

  # Provide an acknowledgement for the context retrieved by requesting others nodes if chain or unspent outputs exists.
  # For the previous transaction chain, the proof of integrity of the previous transaction chain is requested to verify
  # its integrity.
  # For unspent outputs, acknowledgements on the respective origin storage pool is requested to
  # confirm the validity of the transaction
  # In any cases, the additional involved nodes are added to the list of storage nodes to reward.
  defp confirm(
         context = %__MODULE__{previous_chain: [], unspent_outputs: []},
         _,
         _prev_tx_address
       ),
       do: context

  defp confirm(
         context = %__MODULE__{previous_chain: [], unspent_outputs: unspent_outputs},
         _,
         prev_tx_address
       ) do
    %{utxo: confirmed_unspent_outputs, nodes: utxo_storage_nodes} =
      prev_tx_address
      |> confirm_unspent_outputs(unspent_outputs)
      |> reduce_unspent_outputs_confirmation()

    context
    |> Map.put(:unspent_outputs, confirmed_unspent_outputs)
    |> Map.update!(:involved_nodes, fn involved_nodes ->
      involved_nodes
      |> Kernel.++(utxo_storage_nodes)
      |> :lists.flatten()
      |> Enum.uniq()
    end)
  end

  defp confirm(
         context = %__MODULE__{previous_chain: [last_tx | _], unspent_outputs: unspent_outputs},
         previous_chain_storage_nodes,
         prev_tx_address
       ) do
    chain_integrity_task =
      Task.async(fn -> confirm_chain_integrity(last_tx, previous_chain_storage_nodes) end)

    unspent_outputs_task =
      Task.async(fn -> confirm_unspent_outputs(prev_tx_address, unspent_outputs) end)

    with {:ok, confirm_previous_storage_node} <- Task.await(chain_integrity_task),
         confirmed_unspent_outputs <- Task.await(unspent_outputs_task) do
      %{utxo: unspent_outputs, nodes: utxo_storage_nodes} =
        reduce_unspent_outputs_confirmation(confirmed_unspent_outputs)

      confirmation_nodes = [confirm_previous_storage_node | utxo_storage_nodes]

      context
      |> Map.put(:unspent_outputs, unspent_outputs)
      |> Map.update!(:involved_nodes, fn involved_nodes ->
        involved_nodes
        |> Kernel.++(confirmation_nodes)
        |> :lists.flatten()
        |> Enum.uniq_by(& &1)
      end)
    else
      _ ->
        context
    end
  end

  defp closest_storage_nodes(tx_address) do
    {:ok, %Node{network_patch: patch}} = P2P.node_info()

    tx_address
    |> Election.storage_nodes()
    |> P2P.nearest_nodes(patch)
    |> Enum.map(& &1.last_public_key)
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
    case P2P.send_message(storage_node, %GetProofOfIntegrity{address: tx_address}) do
      %ProofOfIntegrity{digest: digest} when poi == digest ->
        {:ok, storage_node}

      %ProofOfIntegrity{} ->
        {:error, :invalid_transaction_chain}

      _ ->
        confirm_chain_integrity(tx, rest)
    end
  end

  defp confirm_chain_integrity(_, []) do
    {:error, :invalid_transaction_chain}
  end

  defp confirm_unspent_outputs(previous_tx_address, unspent_outputs) do
    Task.Supervisor.async_stream_nolink(TaskSupervisor, unspent_outputs, fn utxo ->
      closest_nodes = closest_storage_nodes(utxo.from)
      confirm_unspent_output(previous_tx_address, utxo, closest_nodes)
    end)
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.filter(fn res -> match?({:ok, _, _}, res) end)
    |> Enum.map(fn {:ok, utxo, node} -> {utxo, node} end)
  end

  defp confirm_unspent_output(
         previous_tx_address,
         utxo = %UnspentOutput{from: utxo_address, amount: amount},
         [
           closest_node | rest
         ]
       ) do
    case P2P.send_message(closest_node, %GetTransaction{address: utxo_address}) do
      %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: uco_transfers
            }
          }
        },
        validation_stamp: %ValidationStamp{
          ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
        }
      } ->
        cond do
          Enum.any?(
            uco_transfers,
            &(&1.to == previous_tx_address and &1.amount == amount)
          ) ->
            {:ok, utxo, closest_node}

          Enum.any?(
            transaction_movements,
            &(&1.to == previous_tx_address and &1.amount == amount)
          ) ->
            {:ok, utxo, closest_node}

          true ->
            {:error, :invalid_unspent_output}
        end

      _ ->
        confirm_unspent_output(previous_tx_address, utxo, rest)
    end
  end

  defp confirm_unspent_output(_tx_address, _utxo, []) do
    {:error, :invalid_unspent_output}
  end

  @doc """
  Aggregates a context with another one
  """
  @spec aggregate(__MODULE__.t(), __MODULE__.t()) :: __MODULE__.t()
  def aggregate(context = %__MODULE__{}, new_context = %__MODULE__{}) do
    context
    |> Map.update!(
      :cross_validation_nodes_view,
      &BinarySequence.aggregate(&1, new_context.cross_validation_nodes_view)
    )
    |> Map.update!(
      :chain_storage_nodes_view,
      &BinarySequence.aggregate(&1, new_context.chain_storage_nodes_view)
    )
    |> Map.update!(
      :beacon_storage_nodes_view,
      &BinarySequence.aggregate(&1, new_context.beacon_storage_nodes_view)
    )
    |> Map.update!(:involved_nodes, fn involved_nodes ->
      involved_nodes
      |> Kernel.++(new_context.involved_nodes)
      |> Enum.uniq_by(& &1)
    end)
  end
end
