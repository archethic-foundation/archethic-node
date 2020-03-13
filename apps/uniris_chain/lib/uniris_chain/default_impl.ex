defmodule UnirisChain.DefaultImpl do
  @moduledoc false
  alias UnirisChain.Transaction
  alias UnirisChain.TransactionSupervisor
  alias UnirisChain.TransactionRegistry
  alias __MODULE__.Store
  @behaviour UnirisChain.Impl

  defdelegate child_spec(opts), to: Store

  @impl true
  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    case Registry.lookup(TransactionRegistry, address) do
      [] ->
        case :ets.lookup(:ko_transactions, address) do
          [] ->
            Store.get_transaction(address)

          _ ->
            {:error, :invalid_transaction}
        end

      [{pid, _}] ->
        {:ok, Transaction.get(pid)}
    end
  end

  @impl true
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())}
          | {:error, :transaction_chain_not_exists}
  def get_transaction_chain(address) do
    Store.get_transaction_chain(address)
  end

  @impl true
  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  def get_unspent_output_transactions(address) do
    Store.get_unspent_output_transactions(address)
  end

  @impl true
  @spec store_transaction(Transaction.validated()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    DynamicSupervisor.start_child(TransactionSupervisor, {Transaction, tx})
    Store.store_transaction(tx)
  end

  @impl true
  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(transactions) do
    DynamicSupervisor.start_child(TransactionSupervisor, {Transaction, List.first(transactions)})
    Store.store_transaction_chain(transactions)
  end

  @impl true
  @spec store_ko_transaction(Transaction.validated()) :: :ok
  def store_ko_transaction(%Transaction{address: address, validation_stamp: stamp}) do
    :ets.insert(:ko_transactions, {address, stamp})
    :ok
  end

  @impl true
  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_last_node_shared_secrets_transaction() do
    case Registry.lookup(TransactionRegistry, :node_shared_secrets) do
      [] ->
        Store.get_last_node_shared_secrets_transaction()

      [{pid, _}] ->
        {:ok, Transaction.get(pid)}
    end
  end
end
