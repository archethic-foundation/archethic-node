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
  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_outputs_not_exists}
  def get_unspent_output_transactions(address) do
    impl().get_unspent_output_transactions(address)
  end

  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  @impl true
  def get_last_node_shared_secrets_transaction() do
    impl().get_last_node_shared_secrets_transaction()
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

  @impl true
  @spec node_transactions() :: list(Transaction.validated())
  def node_transactions() do
    impl().node_transactions()
  end

  @impl true
  @spec unspent_outputs_transactions() :: list(Transaction.validated())
  def unspent_outputs_transactions() do
    impl().unspent_outputs_transactions()
  end

  @impl true
  @spec origin_shared_secrets_transactions() :: list(Transaction.validated())
  def origin_shared_secrets_transactions() do
    impl().origin_shared_secrets_transactions()
  end

  defp impl do
    Application.get_env(:uniris_core, UnirisCore.Storage)[:backend]
  end
end
