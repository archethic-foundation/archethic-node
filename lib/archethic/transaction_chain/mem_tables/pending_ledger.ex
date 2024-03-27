defmodule Archethic.TransactionChain.MemTables.PendingLedger do
  @moduledoc """
  Represents a memory table for all the transaction which are in pending state
  awaiting some signatures to be counter-validated
  """

  @table_name :archethic_pending_ledger

  use GenServer
  @vsn 1

  require Logger

  @doc """
  Initialize the memory table

  ## Examples

      iex> PendingLedger.start_link()
      ...> :ets.info(:archethic_pending_ledger)[:type]
      :bag
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Pending Ledger...")

    :ets.new(@table_name, [:bag, :named_table, :public, read_concurrency: true])

    {:ok, %{table_name: @table_name}}
  end

  @doc """
  Add a transaction address as pending.

  ## Examples

      iex> {:ok, pid} = PendingLedger.start_link()
      ...> :ok = PendingLedger.add_address("@Alice2")
      ...> %{table_name: table} = :sys.get_state(pid)
      ...> :ets.tab2list(table)
      [
        {"@Alice2", "@Alice2"}
      ]
  """
  @spec add_address(address :: binary()) :: :ok
  def add_address(address) when is_binary(address) do
    true = :ets.insert(@table_name, {address, address})
    :ok
  end

  @doc """
  Add a signature to a pending transaction.

  The address of the transaction act as signature
  The previous public key is used to determine the previous signing

  ## Examples

      iex> {:ok, _} = PendingLedger.start_link()
      ...> :ok = PendingLedger.add_address("@Alice2")
      ...> :ok = PendingLedger.add_signature("@Alice2", "@Bob3")
      ...> :ets.tab2list(:archethic_pending_ledger)
      [
        {"@Alice2", "@Alice2"},
        {"@Alice2", "@Bob3"}
      ]
  """
  @spec add_signature(pending_tx_address :: binary(), signature_address :: binary()) :: :ok
  def add_signature(pending_tx_address, signature_address)
      when is_binary(pending_tx_address) and is_binary(signature_address) do
    true = :ets.insert(@table_name, {pending_tx_address, signature_address})
    :ok
  end

  @doc """
  Determines if an public key has already a sign for the pending transaction address

  ## Examples

      iex> {:ok, _pid} = PendingLedger.start_link()
      ...> :ok = PendingLedger.add_address("@Alice2")
      ...> :ok = PendingLedger.add_signature("@Alice2", "@Bob3")
      ...> PendingLedger.already_signed?("@Alice2", "@Bob3")
      true
  """
  @spec already_signed?(binary(), binary()) :: boolean()
  def already_signed?(address, signature_address) do
    case :ets.lookup(@table_name, address) do
      [] ->
        false

      res ->
        res
        |> Enum.map(fn {_, signature} -> signature end)
        |> Enum.any?(&(&1 == signature_address))
    end
  end

  @doc """
  Get the list of counter signature for the pending transaction address.

  The counter signatures are transaction addresses validating the the pending transaction

  ## Examples

      iex> {:ok, _pid} = PendingLedger.start_link()
      ...> :ok = PendingLedger.add_address("@Alice2")
      ...> :ok = PendingLedger.add_signature("@Alice2", "@Bob3")
      ...> PendingLedger.get_signatures("@Alice2")
      ["@Alice2", "@Bob3"]
  """
  @spec get_signatures(binary()) :: list(binary())
  def get_signatures(address) when is_binary(address) do
    Enum.map(:ets.lookup(@table_name, address), fn {_, sig} -> sig end)
  end

  @doc """
  Remove a transaction for being a pending one

  ## Examples

      iex> {:ok, _pid} = PendingLedger.start_link()
      ...> :ok = PendingLedger.add_address("@Alice2")
      ...> :ok = PendingLedger.add_signature("@Alice2", "@Bob3")
      ...> PendingLedger.remove_address("@Alice2")
      ...> :ets.tab2list(:archethic_pending_ledger)
      []
  """
  @spec remove_address(binary()) :: :ok
  def remove_address(address) when is_binary(address) do
    true = :ets.delete(@table_name, address)
    :ok
  end
end
