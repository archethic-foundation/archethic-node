defmodule Uniris.Storage.Memory.ChainLookup do
  @moduledoc false

  @table_name :uniris_chain_lookup

  alias Uniris.Crypto

  alias Uniris.Storage.Backend, as: DB

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Chain Lookup...")
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

    DB.list_transaction_chains_info()
    |> Stream.map(fn {address, length} ->
      set_transaction_length(address, length)
      DB.get_transaction_chain(address, [:address, :previous_public_key])
    end)
    |> Stream.flat_map(& &1)
    |> Stream.each(&reverse_link(&1.address, &1.previous_public_key))
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Find out the depth of a transaction chain
  """
  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) do
    case :ets.lookup(@table_name, {:chain_length, address}) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  @doc """
  The the depth of a transaction chain
  """
  @spec set_transaction_length(binary(), non_neg_integer()) :: :ok
  def set_transaction_length(address, length)
      when is_binary(address) and is_integer(length) and length >= 0 do
    true = :ets.insert(@table_name, {{:chain_length, address}, length})
    :ok
  end

  @doc """
  Create link from a previous transaction to a new one using the previous public key 
  to able to lookup to the last transaction of a chain from a genesis address
  """
  @spec reverse_link(address :: binary(), previous_public_key :: binary()) :: :ok
  def reverse_link(address, previous_public_key)
      when is_binary(address) and is_binary(previous_public_key) do
    previous_address = Crypto.hash(previous_public_key)
    true = :ets.insert(@table_name, {previous_address, address})
    true = :ets.insert(@table_name, {address, address})
    :ok
  end

  @doc """
  Retrieve the last transaction address for a chain
  """
  @spec get_last_transaction_address(binary()) :: {:ok, binary()} | {:error, :not_found}
  def get_last_transaction_address(address) when is_binary(address) do
    case :ets.lookup(@table_name, address) do
      [] ->
        {:error, :not_found}

      [{previous, next}] when previous == next ->
        {:ok, address}

      [{_, next}] ->
        get_last_transaction_address(next)
    end
  end
end
