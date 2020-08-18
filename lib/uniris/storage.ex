defmodule Uniris.Storage do
  @moduledoc """
  Manage the access to the transaction storage disk backend storage and in memory
  """
  alias Uniris.Crypto
  alias Uniris.PubSub

  alias __MODULE__.Backend
  alias __MODULE__.Cache

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionInput

  require Logger

  @type unspent_output_options :: [
          transaction_movements: boolean(),
          node_movements: boolean(),
          unspent_outputs: boolean()
        ]

  @doc """
  Return the list of node transactions
  """
  @spec node_transactions() :: list(Transaction.t())
  def node_transactions do
    Cache.list_node_transaction_addresses()
    |> Enum.map(&Backend.get_transaction/1)
    |> Enum.reject(&match?({:error, :transaction_not_exists}, &1))
    |> Enum.map(fn {:ok, tx} -> tx end)
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
    if detect_ko? and Cache.ko_transaction?(address) do
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
  Retrieve unspent outputs for the given address
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) do
    Cache.get_unspent_outputs(address)
  end

  @spec get_inputs(Crypto.key()) :: list(TransactionInput.t())
  def get_inputs(address) do
    Cache.get_ledger_inputs(address)
  end

  @doc """
  Returns the list of origin shared secrets transactions
  """
  @spec origin_shared_secrets_transactions() :: list(Transaction.t())
  def origin_shared_secrets_transactions do
    Cache.list_origin_shared_secrets_addresses()
    |> Enum.map(&Backend.get_transaction/1)
    |> Enum.reject(&match?({:error, :transaction_not_exists}, &1))
    |> Enum.map(fn {:ok, tx} -> tx end)
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
        :ok = Cache.store_transaction(tx)

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
        :ok = Cache.store_transaction(last_tx)
        :ok = Cache.set_transaction_length(last_tx.address, length(chain))

        PubSub.notify_new_transaction(last_tx)

        Logger.info("Transaction Chain #{Base.encode16(last_tx.address)} stored")
    end
  end

  @doc """
  Persist temporary a failed transaction
  """
  @spec write_ko_transaction(Transaction.t(), list()) :: :ok
  def write_ko_transaction(tx = %Transaction{}, additional_errors \\ []) do
    Cache.store_ko_transaction(tx, additional_errors)
  end

  @doc """
  Get the latest node shared secrets transaction including the required nonces
  """
  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_last_node_shared_secrets_transaction do
    case Cache.get_last_node_shared_secrets_address() do
      {:error, :not_found} ->
        {:error, :transaction_not_exists}

      {:ok, address} ->
        Backend.get_transaction(address)
    end
  end

  @spec last_transaction_address(binary()) :: {:ok, binary()} | {:error, :not_found}
  def last_transaction_address(address) do
    Cache.get_last_transaction_address(address)
  end

  @doc """
  Returns the balance of an public key using its unspent output transactions
  """
  @spec balance(binary()) :: float()
  def balance(address) do
    address
    |> Cache.get_ledger_inputs()
    |> Enum.reduce(0.0, &(&2 + &1.amount))
  end

  @doc """
  Return the number of transaction in a chain
  """
  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) do
    Cache.get_transaction_chain_length(address)
  end

  @doc """
  Return the list of code proposals transactions
  """
  @spec list_code_proposals() :: list(Transaction.t())
  def list_code_proposals do
    Cache.list_code_proposals_addresses()
    |> Enum.map(fn address ->
      {:ok, tx} = Backend.get_transaction(address)
      tx
    end)
  end

  @doc """
  Get the list of counter signature for the pending transaction address.

  The counter signatures are transaction addresses validating the the pending transaction
  """
  @spec get_pending_transaction_signatures(binary) :: list(binary())
  def get_pending_transaction_signatures(address) do
    Cache.get_pending_transaction_signatures(address)
  end
end
