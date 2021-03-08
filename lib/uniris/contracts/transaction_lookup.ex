defmodule Uniris.Contracts.TransactionLookup do
  @moduledoc false

  @table_name :uniris_contract_transaction_lookup

  use GenServer

  require Logger

  @doc """
  Initialize the memory tables for the P2P view

  ## Examples

      iex> {:ok, _} = TransactionLookup.start_link()
      iex> :ets.info(:uniris_contract_transaction_lookup)[:type],
      :set
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@table_name, [:bag, :named_table, :public, read_concurrency: true])
    {:ok, []}
  end

  @doc """
  Register a new transaction address towards a contract address
  """
  @spec add_contract_transaction(binary(), binary(), DateTime.t()) :: :ok
  def add_contract_transaction(contract_address, transaction_address, transaction_timestamp)
      when is_binary(contract_address) and is_binary(transaction_address) do
    true =
      :ets.insert(@table_name, {contract_address, transaction_address, transaction_timestamp})

    :ok
  end

  @doc """
  Return the list transaction towards a contract address
  """
  @spec list_contract_transactions(binary()) :: list({binary(), DateTime.t()})
  def list_contract_transactions(contract_address) when is_binary(contract_address) do
    Enum.map(:ets.lookup(@table_name, contract_address), fn {_, tx_address, tx_timestamp} ->
      {tx_address, tx_timestamp}
    end)
  end
end
