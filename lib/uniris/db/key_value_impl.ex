defmodule Uniris.DB.KeyValueImpl do
  @moduledoc false

  use GenServer

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.DBImpl

  alias Uniris.TransactionChain.Transaction
  alias Uniris.Utils

  @behaviour DBImpl

  @transaction_db_name :uniris_kv_db_transactions
  @chain_db_name :uniris_kv_db_chain
  @chain_lookup_db_name :uniris_kv_db_chain_lookup
  @beacon_slot_db_name :uniris_kv_db_beacon_slot
  @beacon_slots_db_name :uniris_kv_db_beacon_slots
  @beacon_summary_db_name :uniris_kv_db_beacon_summary
  @transaction_by_type_table :uniris_kv_transactions_type_lookup
  @chain_public_key_lookup :uniris_kv_chain_public_key_lookup

  require Logger

  @doc """
  Initialize the KV store
  """
  @spec start_link(Keyword.t()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DBImpl
  @doc """
  Retrieve a transaction by address and project the requested fields
  """
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    case :ets.lookup(@transaction_db_name, address) do
      [] ->
        {:error, :transaction_not_exists}

      [{_, tx}] ->
        filter_tx =
          tx
          |> Transaction.to_map()
          |> Utils.take_in(fields)
          |> Transaction.from_map()

        {:ok, filter_tx}
    end
  end

  @impl DBImpl
  @doc """
  Fetch the transaction chain by address and project the requested fields from the transactions
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    Stream.resource(
      fn -> :ets.lookup(@chain_db_name, {:addresses, address}) end,
      fn
        [{_, address} | rest] ->
          {:ok, tx} = get_transaction(address, fields)
          {[tx], rest}

        _ ->
          {:halt, []}
      end,
      fn _ -> :ok end
    )
  end

  @impl DBImpl
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(
        tx = %Transaction{
          address: address,
          type: type,
          timestamp: timestamp,
          previous_public_key: previous_public_key
        }
      ) do
    true = :ets.insert(@transaction_db_name, {address, tx})
    true = :ets.insert(@transaction_by_type_table, {type, address, timestamp})

    previous_address = Crypto.hash(previous_public_key)
    add_last_transaction_address(previous_address, address, Utils.truncate_datetime(timestamp))

    true = :ets.insert(@chain_public_key_lookup, {address, previous_public_key})

    Logger.debug("Transaction stored", transaction: "#{type}@#{Base.encode16(address)}")
    :ok
  end

  @impl DBImpl
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    %Transaction{address: chain_address, type: chain_type} = Enum.at(chain, 0)

    true = :ets.insert(@chain_db_name, {{:size, chain_address}, Enum.count(chain)})

    Stream.each(chain, fn tx = %Transaction{address: address} ->
      true = :ets.insert(@chain_db_name, {{:addresses, chain_address}, address})
      :ok = write_transaction(tx)
    end)
    |> Stream.run()

    Logger.debug(
      "TransactionChain stored (size: #{Enum.count(chain)})",
      transaction: "#{chain_type}@#{Base.encode16(chain_address)}"
    )
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DBImpl
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(previous_tx_address, last_address, timestamp = %DateTime{}) do
    true =
      :ets.insert(
        @chain_lookup_db_name,
        {{:last_transaction, previous_tx_address}, last_address, timestamp}
      )

    :ok
  end

  @doc """
  List the last transaction lookups
  """
  @impl DBImpl
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    :ets.select(@chain_lookup_db_name, [
      {{{:last_transaction, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
    ])
  end

  @impl DBImpl
  @doc """
  List the transactions
  """
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    @transaction_db_name
    |> ets_table_keys()
    |> Stream.map(fn address ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @impl DBImpl
  @spec get_beacon_slots(binary(), DateTime.t()) :: Enumerable.t()
  def get_beacon_slots(subset, from_date = %DateTime{}) when is_binary(subset) do
    Stream.resource(
      fn -> :ets.lookup(@beacon_slots_db_name, subset) end,
      fn
        [{_, slot_time} | rest] ->
          if DateTime.compare(from_date, slot_time) == :gt do
            {:ok, slot} = get_beacon_slot(subset, slot_time)
            {[slot], rest}
          else
            {[], rest}
          end

        _ ->
          {:halt, []}
      end,
      fn _ -> :ok end
    )
  end

  @impl DBImpl
  @spec get_beacon_slot(binary(), DateTime.t()) :: {:ok, Slot.t()} | {:error, :not_found}
  def get_beacon_slot(subset, date = %DateTime{}) when is_binary(subset) do
    case :ets.lookup(@beacon_slot_db_name, {subset, date}) do
      [] ->
        {:error, :not_found}

      [{_, slot}] ->
        {:ok, slot}
    end
  end

  @impl DBImpl
  @spec get_beacon_summary(binary(), DateTime.t()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_beacon_summary(subset, date = %DateTime{}) when is_binary(subset) do
    case :ets.lookup(@beacon_summary_db_name, {subset, date}) do
      [] ->
        {:error, :not_found}

      [{_, summary}] ->
        {:ok, summary}
    end
  end

  @impl DBImpl
  def register_beacon_slot(slot = %Slot{subset: subset, slot_time: slot_time}) do
    true = :ets.insert(@beacon_slot_db_name, {{subset, slot_time}, slot})
    true = :ets.insert(@beacon_slots_db_name, {subset, slot_time})
    :ok
  end

  @impl DBImpl
  @spec register_beacon_summary(Uniris.BeaconChain.Summary.t()) :: :ok
  def register_beacon_summary(summary = %Summary{subset: subset, summary_time: summary_time}) do
    true = :ets.insert(@beacon_summary_db_name, {{subset, summary_time}, summary})

    :ets.lookup(@beacon_slots_db_name, subset)
    |> Enum.filter(&(DateTime.compare(summary_time, elem(&1, 1)) == :gt))
    |> Enum.each(&:ets.delete(@beacon_slot_db_name, &1))

    :ets.delete(@beacon_slots_db_name, subset)

    :ok
  end

  @impl DBImpl
  def migrate do
    :ok
  end

  @impl DBImpl
  def chain_size(address) when is_binary(address) do
    case :ets.lookup(@chain_db_name, {:size, address}) do
      [] ->
        0

      [{_, size}] ->
        size
    end
  end

  @impl DBImpl
  def list_transactions_by_type(type, fields \\ []) do
    Stream.resource(
      fn -> list_addresses_by_type(type) end,
      fn
        [] ->
          {:halt, []}

        [address | rest] ->
          {:ok, tx} = get_transaction(address, fields)
          {[tx], rest}
      end,
      fn _ -> :ok end
    )
  end

  defp list_addresses_by_type(type) do
    @transaction_by_type_table
    |> :ets.lookup(type)
    |> Enum.sort_by(fn {_, _, timestamp} -> timestamp end, {:desc, DateTime})
    |> Enum.map(fn {_, address, _} -> address end)
  end

  @impl DBImpl
  def count_transactions_by_type(type) do
    @transaction_by_type_table
    |> :ets.lookup(type)
    |> Enum.map(fn {_, address, _} -> address end)
    |> length
  end

  @impl DBImpl
  def get_last_chain_address(address) when is_binary(address) do
    case :ets.lookup(@chain_lookup_db_name, {:last_transaction, address}) do
      [] ->
        address

      [{_, next, _}] ->
        get_last_chain_address(next)
    end
  end

  @impl DBImpl
  def get_last_chain_address(address, timestamp = %DateTime{}) when is_binary(address) do
    timestamp = Utils.truncate_datetime(timestamp)

    case :ets.lookup(@chain_lookup_db_name, {:last_transaction, address}) do
      [] ->
        address

      [{_, next_address, next_timestamp}] when next_timestamp == timestamp ->
        next_address

      [{_, next_address, next_timestamp}] ->
        if DateTime.compare(next_timestamp, timestamp) == :gt do
          address
        else
          get_last_chain_address(next_address, timestamp)
        end
    end
  end

  @impl DBImpl
  def get_first_chain_address(address) when is_binary(address) do
    do_get_first_chain_address(address, address)
  end

  defp do_get_first_chain_address(address, prev_address) do
    case :ets.lookup(@chain_public_key_lookup, address) do
      [] ->
        prev_address

      [{_, previous_public_key}] ->
        do_get_first_chain_address(Crypto.hash(previous_public_key), address)
    end
  end

  @impl DBImpl
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

  @impl GenServer
  def init(opts) do
    root_dir = Utils.mut_dir(Keyword.get(opts, :root_dir, "priv/storage"))
    dump_delay = Keyword.get(opts, :dump_delay, 5_000)

    File.mkdir_p!(root_dir)

    init_table(root_dir, @transaction_db_name, :set)
    init_table(root_dir, @chain_db_name, :bag)
    init_table(root_dir, @chain_lookup_db_name, :set)
    init_table(root_dir, @beacon_slot_db_name, :set)
    init_table(root_dir, @beacon_slots_db_name, :bag)
    init_table(root_dir, @beacon_summary_db_name, :set)
    init_table(root_dir, @transaction_by_type_table, :bag)
    init_table(root_dir, @chain_public_key_lookup, :set)

    dump_timer = Process.send_after(self(), :dump, dump_delay)
    {:ok, %{root_dir: root_dir, dump_delay: dump_delay, dump_timer: dump_timer}}
  end

  @impl GenServer
  def handle_info(:dump, state = %{root_dir: root_dir, dump_delay: dump_delay}) do
    Enum.each(
      [
        @transaction_db_name,
        @chain_db_name,
        @chain_lookup_db_name,
        @beacon_slot_db_name,
        @beacon_slots_db_name,
        @beacon_summary_db_name,
        @transaction_by_type_table,
        @chain_public_key_lookup
      ],
      fn table_name ->
        filepath = table_dump_file(root_dir, table_name) |> String.to_charlist()
        :ets.tab2file(table_name, filepath)
      end
    )

    dump_timer = Process.send_after(self(), :dump, dump_delay)

    {:noreply, Map.put(state, :dump_timer, dump_timer), :hibernate}
  end

  defp init_table(root_dir, table_name, type) do
    table_filename = table_dump_file(root_dir, table_name)

    if File.exists?(table_filename) do
      :ets.file2tab(String.to_charlist(table_filename))
    else
      :ets.new(table_name, [:named_table, type, :public, read_concurrency: true])
    end
  end

  defp table_dump_file(root_dir, table_name) do
    Path.join(root_dir, Atom.to_string(table_name))
  end

  defp ets_table_keys(table_name) do
    Stream.resource(
      fn -> :ets.first(table_name) end,
      fn
        :"$end_of_table" -> {:halt, nil}
        previous_key -> {[previous_key], :ets.next(table_name, previous_key)}
      end,
      fn _ -> :ok end
    )
  end
end
