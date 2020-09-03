defmodule Uniris.Storage.Memory.KOLedger do
  @moduledoc false

  @table_name :uniris_ko_ledger

  alias Uniris.Transaction

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory KO Ledger...")

    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    {:ok, []}
  end

  @doc """
  Determine if the transaction address is registered as KO
  """
  @spec has_transaction?(binary()) :: boolean()
  def has_transaction?(address) when is_binary(address) do
    case :ets.lookup(@table_name, address) do
      [] ->
        false

      _ ->
        true
    end
  end

  @doc """
  Retrieve the KO details for a transaction which has not been validated
  """
  @spec get_details(binary()) :: {ValidationStamp.t(), list(), list()}
  def get_details(address) when is_binary(address) do
    case :ets.lookup(@table_name, address) do
      [{_, stamp, inconsistencies, errors}] ->
        {stamp, inconsistencies, errors}

      _ ->
        {nil, []}
    end
  end

  @doc """
  Remove a transaction being KO
  """
  @spec remove_transaction(binary()) :: :ok
  def remove_transaction(address) when is_binary(address) do
    :ets.delete(@table_name, address)
    :ok
  end

  @doc """
  Mark a transaction as KO and include details of the invalidation with its
  validation stamp, inconsistencies from the cross validation nodes and any additional errors
  """
  @spec add_transaction(Transaction.t(), list()) :: :ok
  def add_transaction(
        %Transaction{
          address: tx_address,
          validation_stamp: validation_stamp,
          cross_validation_stamps: stamps
        },
        additional_errors \\ []
      ) do
    inconsistencies =
      stamps
      |> Enum.map(& &1.inconsistencies)
      |> Enum.flat_map(& &1)
      |> Enum.uniq()

    true =
      :ets.insert(
        @table_name,
        {tx_address, validation_stamp, inconsistencies, additional_errors}
      )

    :ok
  end
end
