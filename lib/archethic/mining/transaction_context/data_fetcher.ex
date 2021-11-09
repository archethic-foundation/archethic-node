defmodule ArchEthic.Mining.TransactionContext.DataFetcher do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetP2PView
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.P2PView
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @doc """
  Retrieve the previous transaction and the first node which replied
  """
  @spec fetch_previous_transaction(binary(), list(Node.t())) ::
          {:ok, Transaction.t(), Node.t()} | {:error, :not_found} | {:error, :network_issue}
  def fetch_previous_transaction(previous_address, [node | rest]) do
    message = %GetTransaction{address: previous_address}

    case P2P.send_message(node, message) do
      {:ok, tx = %Transaction{}} ->
        {:ok, tx, node}

      {:ok, %NotFound{}} ->
        {:error, :not_found}

      {:error, _} ->
        fetch_previous_transaction(previous_address, rest)
    end
  end

  def fetch_previous_transaction(_, []), do: {:error, :network_issue}

  @doc """
  Retrieve the previous unspent outputs and the first node which replied
  """
  @spec fetch_unspent_outputs(address :: binary(), storage_nodes :: list(Node.t())) ::
          {:ok, list(UnspentOutput.t()), Node.t()} | {:error, :network_issue}
  def fetch_unspent_outputs(previous_address, [node | rest]) do
    message = %GetUnspentOutputs{address: previous_address}

    case P2P.send_message(node, message) do
      {:ok, %UnspentOutputList{unspent_outputs: utxos}} ->
        {:ok, utxos, node}

      {:error, _} ->
        fetch_unspent_outputs(previous_address, rest)
    end
  end

  def fetch_unspent_outputs(_previous_address, []), do: {:error, :network_issue}

  @doc """
  Request to a set a storage nodes the P2P view of some nodes and the first node which replied
  """
  @spec fetch_p2p_view(
          node_public_keys :: list(Crypto.key()),
          storage_nodes :: list(Node.t())
        ) ::
          {:ok, p2p_view :: bitstring(), node_involved :: Node.t()} | {:error, :network_issue}
  def fetch_p2p_view(node_public_keys, [node | rest]) do
    message = %GetP2PView{node_public_keys: node_public_keys}

    case P2P.send_message(node, message) do
      {:ok, %P2PView{nodes_view: nodes_view}} ->
        {:ok, nodes_view, node}

      {:error, _} ->
        fetch_p2p_view(node_public_keys, rest)
    end
  end

  def fetch_p2p_view(_, []), do: {:error, :network_issue}
end
