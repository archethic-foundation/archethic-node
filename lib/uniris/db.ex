defmodule Uniris.DB do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction

  @spec migrate() :: :ok
  def migrate do
    impl().migrate()
  end

  @doc """
  Get a transaction from the database
  """
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_list(fields) do
    impl().get_transaction(address, fields)
  end

  @doc """
  Get an transaction chain from the database
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    impl().get_transaction_chain(address, fields)
  end

  @doc """
  Flush an entire transaction chain in the database
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    impl().write_transaction_chain(chain)
  end

  @doc """
  Flush a transaction in the database
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    impl().write_transaction(tx)
  end

  @spec write_transaction(Transaction.t(), binary()) :: :ok
  def write_transaction(tx = %Transaction{}, chain_address) do
    impl().write_transaction(tx, chain_address)
  end

  @doc """
  List all the transactions from the database
  """
  @spec list_transactions(fields :: list()) :: Enumerable.t()
  def list_transactions(fields \\ []) do
    impl().list_transactions(fields)
  end

  @doc """
  Determines if the transaction exists
  """
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) when is_binary(address) do
    case get_transaction(address, [:address]) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end

  @doc """
  Reference a last address from a previous address
  """
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(address, last_address, timestamp)
      when is_binary(address) and is_binary(last_address) do
    impl().add_last_transaction_address(address, last_address, timestamp)
  end

  @doc """
  List the last transaction lookups
  """
  @spec list_last_transaction_addresses() :: list({binary(), binary()})
  def list_last_transaction_addresses do
    impl().list_last_transaction_addresses()
  end

  @doc """
  Get a beacon summary by its subset and its date
  """
  @spec get_beacon_summary(binary(), DateTime.t()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_beacon_summary(subset, date = %DateTime{}) when is_binary(subset) do
    impl().get_beacon_summary(subset, date)
  end

  @doc """
  Register a beacon summary
  """
  @spec register_beacon_summary(Summary.t()) :: :ok
  def register_beacon_summary(summary = %Summary{}) do
    impl().register_beacon_summary(summary)
  end

  @doc """
  Register a beacon slot
  """
  @spec register_beacon_slot(Slot.t()) :: :ok
  def register_beacon_slot(slot = %Slot{}) do
    impl().register_beacon_slot(slot)
  end

  @doc """
  Get a beacon slot by its subset and its date
  """
  @spec get_beacon_slot(binary(), DateTime.t()) :: {:ok, Slot.t()} | {:error, :not_found}
  def get_beacon_slot(subset, date = %DateTime{}) when is_binary(subset) do
    impl().get_beacon_slot(subset, date)
  end

  @doc """
  Get all the beacon slots for the given subset before a given date
  """
  @spec get_beacon_slots(binary(), DateTime.t()) :: Enumerable.t()
  def get_beacon_slots(subset, from_date = %DateTime{}) when is_binary(subset) do
    impl().get_beacon_slots(subset, from_date)
  end

  @doc """
  Return the size of a transaction chain
  """
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) when is_binary(address) do
    impl().chain_size(address)
  end

  @doc """
  List all the transaction for a given transaction type sorted by timestamp in descent order
  """
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    impl().list_transactions_by_type(type, fields)
  end

  @doc """
  Get the number of transactions for a given type
  """
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    impl().count_transactions_by_type(type)
  end

  @doc """
  Get the last transaction address from a transaction chain
  """
  @spec get_last_chain_address(binary()) :: binary()
  def get_last_chain_address(address) when is_binary(address) do
    impl().get_last_chain_address(address)
  end

  @doc """
  Get the last transaction address from a transaction chain before a given date
  """
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, timestamp) when is_binary(address) do
    impl().get_last_chain_address(address, timestamp)
  end

  @doc """
  Get the first transaction address from a transaction chain
  """
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    impl().get_first_chain_address(address)
  end

  @doc """
  Get the first public key from one the public key of the chainn
  """
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(public_key) when is_binary(public_key) do
    impl().get_first_public_key(public_key)
  end

  @doc """
  Register a new transaction per second for the given date and the number of transactions
  """
  @spec register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
  def register_tps(date = %DateTime{}, tps, nb_transactions)
      when is_float(tps) and is_integer(nb_transactions) do
    impl().register_tps(date, tps, nb_transactions)
  end

  @doc """
  Retreive the number of transactions in the network
  """
  @spec get_nb_transactions() :: non_neg_integer()
  def get_nb_transactions do
    impl().get_nb_transactions()
  end

  @doc """
  Retrieve the last TPS
  """
  @spec get_latest_tps() :: float()
  def get_latest_tps do
    impl().get_latest_tps
  end

  defp impl do
    Application.get_env(:uniris, __MODULE__)[:impl]
  end
end
