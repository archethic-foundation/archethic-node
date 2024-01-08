defmodule Archethic.Contracts.TransactionLookup do
  @moduledoc false

  @table_name :archethic_contract_transaction_lookup

  use GenServer
  @vsn 1

  alias Archethic.DB
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  require Logger

  @doc """
  Initialize the memory tables for the P2P view

  ## Examples

      iex> {:ok, _} = TransactionLookup.start_link()
      iex> :ets.info(:archethic_contract_transaction_lookup)[:type],
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
  @spec add_contract_transaction(
          contract_address :: binary(),
          tx_address :: binary(),
          tx_timestamp :: DateTime.t(),
          protocol_version :: pos_integer()
        ) :: :ok
  def add_contract_transaction(
        contract_address,
        transaction_address,
        transaction_timestamp,
        protocol_version
      )
      when is_binary(contract_address) and is_binary(transaction_address) do
    true =
      :ets.insert(
        @table_name,
        {contract_address, transaction_address, transaction_timestamp, protocol_version}
      )

    :ok
  end

  @doc """
  Return the list transaction towards a contract address
  """
  @spec list_contract_transactions(binary()) ::
          list(
            {address :: binary(), timestamp :: DateTime.t(), protocol_version :: pos_integer()}
          )
  def list_contract_transactions(contract_address) when is_binary(contract_address) do
    case :ets.lookup(@table_name, contract_address) do
      [] ->
        DB.get_inputs(:call, contract_address)
        |> Enum.map(fn %VersionedTransactionInput{
                         input: %TransactionInput{from: from, timestamp: timestamp},
                         protocol_version: protocol_version
                       } ->
          {from, timestamp, protocol_version}
        end)

      inputs ->
        Enum.map(inputs, fn {_, tx_address, tx_timestamp, protocol_version} ->
          {tx_address, tx_timestamp, protocol_version}
        end)
    end
  end

  @doc """
  Remove the contract transactions
  """
  @spec clear_contract_transactions(binary()) :: :ok
  def clear_contract_transactions(contract_address) when is_binary(contract_address) do
    {:ok, pid} = DB.start_inputs_writer(:call, contract_address)

    contract_address
    |> list_contract_transactions()
    |> Enum.each(fn {tx_address, tx_timestamp, protocol_version} ->
      input = %VersionedTransactionInput{
        input: %TransactionInput{
          from: tx_address,
          timestamp: tx_timestamp,
          type: :call
        },
        protocol_version: protocol_version
      }

      DB.append_input(pid, input)
    end)

    DB.stop_inputs_writer(pid)

    :ets.delete(@table_name, contract_address)
    :ok
  end
end
