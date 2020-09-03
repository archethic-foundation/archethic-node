defmodule Uniris.Storage do
  @moduledoc """
  Handle transaction storage
  """
  alias Uniris.Crypto

  alias Uniris.PubSub

  alias __MODULE__.Backend

  alias __MODULE__.Memory
  alias __MODULE__.Memory.ChainLookup
  alias __MODULE__.Memory.KOLedger
  alias __MODULE__.Memory.NetworkLedger
  alias __MODULE__.Memory.PendingLedger
  alias __MODULE__.Memory.UCOLedger

  alias Uniris.SharedSecretsRenewal

  alias Uniris.Transaction
  alias Uniris.TransactionData
  alias Uniris.TransactionData.Keys

  require Logger

  @doc """
  Return the list of node transactions
  """
  @spec node_transactions() :: Enumerable.t()
  def node_transactions do
    Memory.NetworkLedger.list_node_transactions()
    |> Stream.map(&Backend.get_transaction/1)
    |> Stream.reject(&match?({:error, :transaction_not_exists}, &1))
    |> Stream.map(fn {:ok, tx} -> tx end)
  end

  @doc """
  Return the list of transactions stored
  """
  @spec list_transactions(limit :: non_neg_integer()) :: Enumerable.t()
  def list_transactions(limit \\ 0)

  def list_transactions(0) do
    Backend.list_transactions()
  end

  def list_transactions(limit) do
    Backend.list_transactions() |> Stream.take(limit)
  end

  @doc """
  Retrieve a transaction by its address
  """
  @spec get_transaction(address :: binary(), detect_ko? :: boolean()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :invalid_transaction}
  def get_transaction(address, detect_ko? \\ true) do
    if detect_ko? and KOLedger.has_transaction?(address) do
      {:error, :invalid_transaction}
    else
      Backend.get_transaction(address)
    end
  end

  @doc """
  Retrieve an entire chain from the last transaction
  The returned list is ordered chronologically.
  """
  @spec get_transaction_chain(binary()) :: list(Transaction.t())
  def get_transaction_chain(address) do
    Backend.get_transaction_chain(address)
  end

  @doc """
  Persist only one transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    case get_transaction(tx.address) do
      {:ok, _} ->
        Logger.info("Transaction #{Base.encode16(tx.address)} already stored")
        :ok

      _ ->
        :ok = Backend.write_transaction(tx)
        :ok = index_transaction(tx)

        PubSub.notify_new_transaction(tx)

        Logger.info("Transaction #{tx.type}@#{Base.encode16(tx.address)} stored")
    end
  end

  @doc """
  Persist a new transaction chain
  """
  @spec write_transaction_chain(list(Transaction.t())) ::
          :ok
  def write_transaction_chain([last_tx = %Transaction{} | _] = chain)
      when is_list(chain) do
    case get_transaction(last_tx.address, false) do
      {:ok, _} ->
        Logger.info("Transaction #{Base.encode16(last_tx.address)} already stored")
        :ok

      _ ->
        :ok = Backend.write_transaction_chain(chain)
        :ok = index_transaction(last_tx)
        :ok = ChainLookup.set_transaction_length(last_tx.address, length(chain))

        PubSub.notify_new_transaction(last_tx)

        Logger.info("Transaction Chain #{Base.encode16(last_tx.address)} stored")
    end
  end

  # Index the transaction in the memory into several ledgers and lookups table
  defp index_transaction(
         tx = %Transaction{address: address, previous_public_key: previous_public_key}
       ) do
    ChainLookup.reverse_link(address, previous_public_key)
    UCOLedger.distribute_unspent_outputs(tx)
    index_by_type(tx)
  end

  defp index_by_type(tx = %Transaction{type: :node, previous_public_key: previous_public_key}) do
    NetworkLedger.load_transaction(tx)

    first_public_key =
      NetworkLedger.get_node_first_public_key_from_previous_key(previous_public_key)

    if first_public_key == Crypto.node_public_key(0) do
      Crypto.increment_number_of_generate_node_keys()
      Logger.info("Node key index incremented")
    else
      :ok
    end
  end

  defp index_by_type(
         tx = %Transaction{
           type: :node_shared_secrets,
           timestamp: timestamp,
           data: %TransactionData{
             keys: %Keys{
               secret: secret,
               authorized_keys: authorized_keys
             }
           }
         }
       ) do
    NetworkLedger.load_transaction(tx)
    Crypto.increment_number_of_generate_node_shared_secrets_keys()

    case Map.get(authorized_keys, Crypto.node_public_key()) do
      nil ->
        :ok

      encrypted_key ->
        SharedSecretsRenewal.schedule_node_renewal_application(
          Map.keys(authorized_keys),
          encrypted_key,
          secret,
          timestamp
        )
    end
  end

  defp index_by_type(tx = %Transaction{type: :origin_shared_secrets}) do
    NetworkLedger.load_transaction(tx)
  end

  defp index_by_type(tx = %Transaction{address: address, type: :code_proposal}) do
    NetworkLedger.load_transaction(tx)
    PendingLedger.add_address(address)
  end

  defp index_by_type(_), do: :ok

  @doc """
  Return the list of code proposals transactions
  """
  @spec list_code_proposals() :: Enumerable.t()
  def list_code_proposals do
    NetworkLedger.list_code_proposals_addresses()
    |> Stream.map(fn address ->
      {:ok, tx} = Backend.get_transaction(address)
      tx
    end)
  end
end
