defmodule Archethic.TransactionChain.MemTables.KOLedger do
  @moduledoc """
  Represents an memory table will all the invalid transactions and their reasons
  """

  @table_name :archethic_ko_ledger

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  use GenServer
  @vsn 1

  require Logger

  @doc """
  Initialize the memory table for the invalid transactions (KO)

  ## Examples

      iex> {:ok, _} = KOLedger.start_link()
      ...> :ets.info(:archethic_ko_ledger)[:type]
      :set
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    Logger.info("Initialize InMemory KO Ledger...")

    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    {:ok, []}
  end

  @doc """
  Determine if the transaction address is registered as KO

  ## Examples

      iex> KOLedger.start_link()
      ...> 
      ...> :ok =
      ...>   KOLedger.add_transaction(%Transaction{
      ...>     address: "@Alice1",
      ...>     validation_stamp: %ValidationStamp{},
      ...>     cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
      ...>   })
      ...> 
      ...> KOLedger.has_transaction?("@Alice1")
      true
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

  ## Examples

      iex> KOLedger.start_link()
      ...> 
      ...> :ok =
      ...>   KOLedger.add_transaction(%Transaction{
      ...>     address: "@Alice1",
      ...>     validation_stamp: %ValidationStamp{},
      ...>     cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
      ...>   })
      ...> 
      ...> KOLedger.get_details("@Alice1")
      {%ValidationStamp{}, [:proof_of_work], []}
  """
  @spec get_details(binary()) ::
          {ValidationStamp.t(), inconsistencies :: list(), errors :: list()}
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

  ## Examples

      iex> KOLedger.start_link()
      ...> 
      ...> :ok =
      ...>   KOLedger.add_transaction(%Transaction{
      ...>     address: "@Alice1",
      ...>     validation_stamp: %ValidationStamp{},
      ...>     cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
      ...>   })
      ...> 
      ...> :ok = KOLedger.remove_transaction("@Alice1")
      ...> KOLedger.has_transaction?("@Alice1")
      false
  """
  @spec remove_transaction(binary()) :: :ok
  def remove_transaction(address) when is_binary(address) do
    :ets.delete(@table_name, address)
    :ok
  end

  @doc """
  Mark a transaction as KO and include details of the invalidation with its
  validation stamp, inconsistencies from the cross validation nodes and any additional errors

  ## Examples

      iex> KOLedger.start_link()
      ...> 
      ...> :ok =
      ...>   KOLedger.add_transaction(%Transaction{
      ...>     address: "@Alice1",
      ...>     validation_stamp: %ValidationStamp{},
      ...>     cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
      ...>   })
      ...> 
      ...> :ets.tab2list(:archethic_ko_ledger)
      [
        {"@Alice1", %ValidationStamp{}, [:proof_of_work], []}
      ]
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

    Logger.info("KO transaction #{Base.encode16(tx_address)}")
    :ok
  end
end
