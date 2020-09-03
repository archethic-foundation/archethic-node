defmodule Uniris.Storage.Backend do
  @moduledoc false

  alias Uniris.Transaction

  @behaviour Uniris.Storage.BackendImpl

  @impl true
  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(args) do
    impl().child_spec(args)
  end

  @impl true
  @spec migrate() :: :ok
  def migrate do
    impl().migrate()
  end

  @impl true
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_list(fields) do
    impl().get_transaction(address, fields)
  end

  @impl true
  @spec get_transaction_chain(binary(), list()) :: list(Transaction.t())
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    impl().get_transaction_chain(address, fields)
  end

  @impl true
  @spec write_transaction_chain(list(Transaction.t())) :: :ok
  def write_transaction_chain(txs) when is_list(txs) do
    impl().write_transaction_chain(txs)
  end

  @impl true
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    impl().write_transaction(tx)
  end

  @impl true
  @spec list_transactions(fields :: list()) :: Enumerable.t()
  def list_transactions(fields \\ []) do
    impl().list_transactions(fields)
  end

  @impl true
  @spec list_transactions() ::
          list({last_transaction_address :: binary(), nb_transactions :: non_neg_integer()})
  def list_transaction_chains_info do
    impl().list_transaction_chains_info()
  end

  @impl true
  @spec list_transactions_by_type(type :: Transaction.type(), fields :: list()) :: Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    impl().list_transactions_by_type(type, fields)
  end

  defp impl do
    Application.get_env(:uniris, __MODULE__)[:impl]
  end
end
