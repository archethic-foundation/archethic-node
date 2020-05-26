defmodule UnirisCore.Storage.Backend do
  @moduledoc false

  alias UnirisCore.Transaction

  @behaviour UnirisCore.Storage.BackendImpl

  @impl true
  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    impl().get_transaction(address)
  end

  @impl true
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :transaction_chain_not_exists}
  def get_transaction_chain(address) when is_binary(address) do
    impl().get_transaction_chain(address)
  end

  @impl true
  @spec write_transaction_chain(list(Transaction.validated())) :: :ok
  def write_transaction_chain(txs) when is_list(txs) do
    impl().write_transaction_chain(txs)
  end

  @impl true
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    impl().write_transaction(tx)
  end

  @impl true
  @spec list_transactions() :: list(Transaction.validated())
  def list_transactions() do
    impl().list_transactions()
  end

  defp impl do
    Application.get_env(:uniris_core, UnirisCore.Storage)[:backend]
  end
end
