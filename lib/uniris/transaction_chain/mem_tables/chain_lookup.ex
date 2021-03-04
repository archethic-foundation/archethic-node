defmodule Uniris.TransactionChain.MemTables.ChainLookup do
  @moduledoc """
  Represents a Memory Table to index transaction chains
  """

  @chain_genesis_lookup :uniris_chain_genesis_lookup
  @chain_public_key_lookup :uniris_chain_public_key_lookup
  @chain_info_table :uniris_chain_info_lookup
  @transaction_by_type_table :uniris_transactions_by_type_lookup
  @transaction_by_type_counter :uniris_transactions_by_type_counter

  alias Uniris.Crypto
  alias Uniris.TransactionChain.Transaction

  use GenServer

  require Logger

  @doc """
  Initialize the memory tables for the P2P view

  ## Examples

      iex> {:ok, _} = ChainLookup.start_link()
      iex> {
      ...>    :ets.info(:uniris_chain_genesis_lookup)[:type],
      ...>    :ets.info(:uniris_chain_public_key_lookup)[:type],
      ...>    :ets.info(:uniris_chain_info_lookup)[:type],
      ...>    :ets.info(:uniris_transactions_by_type_lookup)[:type],
      ...>    :ets.info(:uniris_transactions_by_type_counter)[:type]
      ...>  }
      { :set, :set, :set, :bag, :set }
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Chain Lookup...")
    :ets.new(@chain_genesis_lookup, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@chain_info_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@chain_public_key_lookup, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@transaction_by_type_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@transaction_by_type_counter, [:set, :named_table, :public, read_concurrency: true])

    {:ok, []}
  end

  @doc """
  Find out the depth of a transaction chain

  ## Examples

      iex> {:ok, _} = ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> ChainLookup.get_chain_length(Crypto.hash("Alice3"))
      3
  """
  @spec get_chain_length(binary()) :: non_neg_integer()
  def get_chain_length(address) do
    do_get_chain_length(address, 0)
  end

  defp do_get_chain_length(address, acc) do
    case :ets.lookup(@chain_public_key_lookup, address) do
      [] ->
        acc

      [{_, previous_public_key}] ->
        do_get_chain_length(Crypto.hash(previous_public_key), acc + 1)
    end
  end

  @doc """
  Retrieve the last transaction address for a chain

  ## Examples

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> ChainLookup.get_last_chain_address(Crypto.hash("Alice1"))
      Crypto.hash("Alice3")

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> ChainLookup.get_last_chain_address(Crypto.hash("Alice1"))
      Crypto.hash("Alice1")
  """
  @spec get_last_chain_address(binary()) :: binary()
  def get_last_chain_address(address) when is_binary(address) do
    case :ets.lookup(@chain_genesis_lookup, address) do
      [] ->
        address

      [{_, next}] ->
        get_last_chain_address(next)
    end
  end

  @doc """
  Retrieve the first transaction address for a chain

  ## Examples

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> ChainLookup.get_first_chain_address(Crypto.hash("Alice3"))
      Crypto.hash("Alice0")
  """
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    do_get_first_chain_address(address, address)
  end

  defp do_get_first_chain_address(address, prev_address) do
    case :ets.lookup(@chain_public_key_lookup, address) do
      [] ->
        prev_address

      [{_, previous_public_key}] ->
        get_first_chain_address(Crypto.hash(previous_public_key))
    end
  end

  @doc """
  Create link from a previous transaction to a new one using the previous public key
  to able to lookup to the last transaction of a chain from a genesis address

  ## Examples

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> {:ets.tab2list(:uniris_chain_public_key_lookup), :ets.tab2list(:uniris_chain_genesis_lookup)}
      {
        # Public key lookup
        [
          {Crypto.hash("Alice1"), "Alice0"},
          {Crypto.hash("Alice2"), "Alice1"}
        ],
        # Genesis lookup
        [
          {Crypto.hash("Alice1"), Crypto.hash("Alice2")},
          {Crypto.hash("Alice0"), Crypto.hash("Alice1")}
        ]
      }

  """
  @spec reverse_link(address :: binary(), previous_public_key :: binary()) :: :ok
  def reverse_link(address, previous_public_key)
      when is_binary(address) and is_binary(previous_public_key) do
    previous_address = Crypto.hash(previous_public_key)

    :ok = register_last_address(previous_address, address)
    true = :ets.insert(@chain_public_key_lookup, {address, previous_public_key})

    :ok
  end

  @doc """
  Create link between a transaction address and the last transaction of its chain

  ## Examples

      iex> ChainLookup.start_link()
      iex> ChainLookup.register_last_address("@Alice1", "@Alice10")
      iex> ChainLookup.get_last_chain_address("@Alice1")
      "@Alice10"
  """
  @spec register_last_address(binary(), binary()) :: :ok
  def register_last_address(address, last_address) do
    true = :ets.insert(@chain_genesis_lookup, {address, last_address})
    :ok
  end

  @doc """
  Get the first public key of a chain

  ## Examples

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> ChainLookup.get_first_public_key("Alice2")
      "Alice0"

    Returns the previous public key if there is not previous transaction related to the public key

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      iex> ChainLookup.get_first_public_key("Alice0")
      "Alice0"

  """
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(previous_public_key) when is_binary(previous_public_key) do
    previous_address = Crypto.hash(previous_public_key)

    case :ets.lookup(@chain_public_key_lookup, previous_address) do
      [] ->
        previous_public_key

      [{_, previous_public_key}] ->
        case get_first_public_key(previous_public_key) do
          key ->
            key
        end
    end
  end

  @doc """
  List the transaction addresses for a given type of transaction sorted by timestamp in descent order

  ## Examples

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.add_transaction_by_type("@Alice1", :transfer, ~U[2020-10-23 01:15:36.494147Z])
      iex> :ok = ChainLookup.add_transaction_by_type("@Bob3", :transfer, ~U[2020-10-23 01:15:36.494147Z])
      iex> :ok = ChainLookup.add_transaction_by_type("@Charlie10", :transfer, ~U[2020-10-23 01:22:24.625931Z])
      iex> ChainLookup.list_addresses_by_type(:transfer)
      [ "@Charlie10", "@Alice1", "@Bob3" ]
  """
  @spec list_addresses_by_type(Transaction.transaction_type()) :: list(binary())
  def list_addresses_by_type(type) when is_atom(type) do
    @transaction_by_type_table
    |> :ets.lookup(type)
    |> Enum.sort_by(fn {_, _, timestamp} -> timestamp end, {:desc, DateTime})
    |> Enum.map(fn {_, address, _} -> address end)
  end

  @doc """
  Get the number of transactions for a given type

  ## Examples

      iex> {:ok, _} = ChainLookup.start_link()
      iex> :ok = ChainLookup.add_transaction_by_type("@Alice1", :transfer, ~U[2020-10-23 01:15:36.494147Z])
      iex> :ok = ChainLookup.add_transaction_by_type("@Bob3", :transfer, ~U[2020-10-23 01:15:36.494147Z])
      iex> ChainLookup.count_addresses_by_type(:transfer)
      2
  """
  @spec count_addresses_by_type(Transaction.transaction_type()) :: non_neg_integer()
  def count_addresses_by_type(type) when is_atom(type) do
    case :ets.lookup(@transaction_by_type_counter, type) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  @doc """
  Reference transaction address by type and timestamp and increment a type counter

  ## Examples

      iex> {:ok, _} = ChainLookup.start_link()
      iex> :ok = ChainLookup.add_transaction_by_type("@Alice1", :transfer, ~U[2020-10-23 01:15:36.494147Z])
      iex> :ok = ChainLookup.add_transaction_by_type("@Bob3", :transfer, ~U[2020-10-23 01:15:36.494147Z])
      iex> { :ets.tab2list(:uniris_transactions_by_type_lookup), :ets.tab2list(:uniris_transactions_by_type_counter) }
      {
        [
          { :transfer, "@Alice1", ~U[2020-10-23 01:15:36.494147Z]},
          { :transfer, "@Bob3", ~U[2020-10-23 01:15:36.494147Z]}
        ],
        [{ :transfer, 2 }]
      }
  """
  @spec add_transaction_by_type(
          address :: binary(),
          type :: Transaction.transaction_type(),
          timestamp :: DateTime.t()
        ) :: :ok
  def add_transaction_by_type(address, type, timestamp = %DateTime{})
      when is_binary(address) and is_atom(type) do
    true = :ets.insert(@transaction_by_type_table, {type, address, timestamp})
    :ets.update_counter(@transaction_by_type_counter, type, {2, 1}, {type, 0})
    :ok
  end

  @doc """
  Determines if the transaction already have been indexed

  ## Examples

      iex> ChainLookup.start_link()
      iex> :ok = ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      iex> ChainLookup.transaction_exists?(Crypto.hash("Alice3"))
      true

      iex> ChainLookup.start_link()
      iex> ChainLookup.transaction_exists?(Crypto.hash("Bob3"))
      false
  """
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) when is_binary(address) do
    :ets.member(@chain_genesis_lookup, address) or :ets.member(@chain_public_key_lookup, address)
  end
end
