defmodule Uniris.DB do
  @moduledoc false

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
  @spec write_transaction_chain(Enumerable.t()) :: :ok | {:error, :transaction_already_exists}
  def write_transaction_chain(chain) do
    %Transaction{address: last_address} = Enum.at(chain, 0)

    case get_transaction(last_address, [:type]) do
      {:ok, _} ->
        {:error, :transaction_already_exists}

      _ ->
        :ok = impl().write_transaction_chain(chain)
    end
  end

  @doc """
  Flush a transaction in the database
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{address: tx_address}) do
    case get_transaction(tx_address, [:type]) do
      {:ok, _} ->
        {:error, :transaction_already_exists}

      _ ->
        impl().write_transaction(tx)
    end
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

  defp impl do
    Application.get_env(:uniris, __MODULE__)[:impl]
  end
end
