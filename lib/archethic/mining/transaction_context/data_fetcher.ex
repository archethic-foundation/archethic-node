defmodule Archethic.Mining.TransactionContext.DataFetcher do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  @doc """
  Retrieve the previous transaction and the first node which replied
  """
  @spec fetch_previous_transaction(binary(), list(Node.t())) ::
          {:ok, Transaction.t(), Node.t()}
          | {:error, :not_found}
          | {:error, :invalid_transaction}
          | {:error, :network_issue}
  def fetch_previous_transaction(previous_address, [node | rest]) do
    message = %GetTransaction{address: previous_address}

    case P2P.send_message(node, message, 500) do
      {:ok, tx = %Transaction{}} ->
        {:ok, tx, node}

      {:ok, %NotFound{}} ->
        {:error, :not_found}

      {:ok, %Error{reason: :invalid_transaction}} ->
        {:error, :invalid_transaction}

      {:error, _} ->
        fetch_previous_transaction(previous_address, rest)
    end
  end

  def fetch_previous_transaction(_, []), do: {:error, :network_issue}

  @doc """
  Retrieve the previous unspent outputs and the first node which replied.
  """
  @spec fetch_unspent_outputs(address :: binary(), storage_nodes :: list(Node.t())) ::
          {:ok, list(UnspentOutput.t()), Node.t()} | {:error, :network_issue}
  def fetch_unspent_outputs(previous_address, [node | rest]) do
    message = %GetUnspentOutputs{address: previous_address}

    case P2P.send_message(node, message, 500) do
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
  @spec fetch_p2p_view(node_public_keys :: list(Crypto.key())) :: bitstring()
  def fetch_p2p_view(node_public_keys) do
    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      node_public_keys,
      fn node_public_key ->
        P2P.send_message(node_public_key, %Ping{}, 500)
      end,
      on_timeout: :kill_task,
      timeout: 500
    )
    |> Enum.map(fn
      {:ok, {:ok, %Ok{}}} -> <<1::1>>
      _ -> <<0::1>>
    end)
    |> :erlang.list_to_bitstring()
  end
end
