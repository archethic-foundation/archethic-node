defmodule Uniris.Replication.TransactionContext do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.TransactionChain.TransactionInput

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Uniris.Replication

  @doc """
  Fetch transaction chain
  """
  @spec fetch_transaction_chain(address :: Crypto.versioned_hash()) ::
          Enumerable.t() | list(Transaction.t())
  def fetch_transaction_chain(address) when is_binary(address) do
    address
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
    |> P2P.nearest_nodes()
    |> P2P.broadcast_message(%GetTransactionChain{address: address})
    |> Stream.take(1)
    |> Stream.flat_map(fn %TransactionList{transactions: transactions} -> transactions end)
  end

  @doc """
  Fetch the transaction unspent outputs
  """
  @spec fetch_unspent_outputs(address :: Crypto.versioned_hash()) ::
          Enumerable.t() | list(UnspentOutput.t())
  def fetch_unspent_outputs(address) when is_binary(address) do
    address
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
    |> P2P.nearest_nodes()
    |> P2P.broadcast_message(%GetUnspentOutputs{address: address})
    |> Stream.take(1)
    |> Enum.flat_map(fn %UnspentOutputList{unspent_outputs: unspent_outputs} ->
      unspent_outputs
    end)
  end

  @spec fetch_transaction_inputs(binary()) :: list(TransactionInput.t())
  def fetch_transaction_inputs(address) when is_binary(address) do
    address
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
    |> P2P.nearest_nodes()
    |> P2P.broadcast_message(%GetTransactionInputs{address: address})
    |> Stream.take(1)
    |> Stream.flat_map(fn %TransactionInputList{inputs: inputs} ->
      inputs
    end)
  end
end
