defmodule UnirisCore.Storage do
  alias UnirisCore.Transaction
  alias __MODULE__.Backend
  alias __MODULE__.Cache
  alias UnirisCore.PubSub

  require Logger

  @doc """
  Return the list of node transactions
  """
  @spec node_transactions() :: list(Transaction.validated())
  def node_transactions() do
    case Cache.node_transactions() do
      [] ->
        Backend.node_transactions()

      transactions ->
        transactions
    end
  end

  @doc """
  Return the list of transactions stored
  """
  @spec list_transactions() :: list(Transaction.validated())
  def list_transactions() do
    Backend.list_transactions()
  end

  @doc """
  Retrieve a transaction by its address
  """
  @spec get_transaction(binary()) :: {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    case Cache.get_transaction(address) do
      nil ->
        if Cache.ko_transaction?(address) do
          {:error, :invalid_transaction}
        else
          Backend.get_transaction(address)
        end

      transaction ->
        {:ok, transaction}
    end
  end

  @doc """
  Retrieve an entire chain from the last transaction
  The returned list is ordered chronologically.
  """
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.t())} | {:error, :transaction_chain_not_exists}
  def get_transaction_chain(address) do
    Backend.get_transaction_chain(address)
  end

  @doc """
  Retrieve unspent outputs with destination of transfers for the given address
  """
  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  def get_unspent_output_transactions(address) do
    case Cache.get_unspent_outputs(address) do
      [] ->
        Backend.get_unspent_output_transactions(address)

      unspent_outputs ->
        {:ok, unspent_outputs}
    end
  end

  @doc """
  Returns the list of origin shared secrets transactions
  """
  @spec origin_shared_secrets_transactions() :: list(Transaction.validated())
  def origin_shared_secrets_transactions() do
    case Cache.origin_shared_secrets_transactions() do
      [] ->
        Backend.origin_shared_secrets_transactions()

      transactions ->
        {:ok, transactions}
    end
  end

  @doc """
  Persist only one transaction
  """
  @spec write_transaction(Transaction.t(), load_transaction? :: boolean()) :: :ok
  def write_transaction(tx = %Transaction{}, load_transaction? \\ true) do
    case get_transaction(tx.address) do
      {:ok, _} ->
        :ok

      _ ->
        :ok = Backend.write_transaction(tx)
        :ok = Cache.store_transaction(tx)

        if load_transaction? do
          PubSub.notify_new_transaction(tx)
        end

        Logger.debug("Transaction #{tx.type}@#{Base.encode16(tx.address)} stored")
    end
  end

  @doc """
  Persist a new transaction chain
  """
  @spec write_transaction_chain(list(Transaction.validated()), load_transaction? :: boolean()) ::
          :ok
  def write_transaction_chain([last_tx | _] = chain, load_transaction? \\ false)
      when is_list(chain) do
    case get_transaction(last_tx) do
      {:ok, _} ->
        :ok

      _ ->
        :ok = Backend.write_transaction_chain(chain)
        :ok = Cache.store_transaction(last_tx)

        if load_transaction? do
          PubSub.notify_new_transaction(last_tx)
        end

        Logger.debug("Transaction Chain #{Base.encode16(last_tx.address)} stored")
    end
  end

  @doc """
  Persist temporary a failed transaction
  """
  @spec write_ko_transaction(Transaction.t()) :: :ok
  def write_ko_transaction(tx = %Transaction{}) do
    Cache.store_ko_transaction(tx)
  end

  @doc """
  Get the latest node shared secrets transaction including the required nonces
  """
  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_last_node_shared_secrets_transaction() do
    case Cache.last_node_shared_secrets_transaction() do
      nil ->
        Backend.get_last_node_shared_secrets_transaction()

      tx ->
        {:ok, tx}
    end
  end
end
