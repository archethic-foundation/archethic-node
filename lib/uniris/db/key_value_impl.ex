defmodule Uniris.DB.KeyValueImpl do
  @moduledoc false

  use GenServer

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

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
      fn -> :ets.lookup(@chain_db_name, address) end,
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
  def write_transaction(tx = %Transaction{address: address}) do
    true = :ets.insert(@transaction_db_name, {address, tx})
    Logger.debug("Transaction #{Base.encode16(address)} stored")
    :ok
  end

  @impl DBImpl
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    %Transaction{address: chain_address} = Enum.at(chain, 0)

    Stream.each(chain, fn tx = %Transaction{address: address} ->
      true = :ets.insert(@chain_db_name, {chain_address, address})
      :ok = write_transaction(tx)
    end)
    |> Stream.run()

    Logger.debug(
      "TransactionChain #{Base.encode16(chain_address)} stored (size: #{Enum.count(chain)})"
    )
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DBImpl
  @spec add_last_transaction_address(binary(), binary()) :: :ok
  def add_last_transaction_address(tx_address, last_address) do
    true = :ets.insert(@chain_lookup_db_name, {{:last_transaction, tx_address}, last_address})
    :ok
  end

  @doc """
  List the last transaction lookups
  """
  @impl DBImpl
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    :ets.select(@chain_lookup_db_name, [
      {{{:last_transaction, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
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

    Process.send_after(self(), :dump, dump_delay)
    {:ok, %{root_dir: root_dir, dump_delay: dump_delay}}
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
        @beacon_summary_db_name
      ],
      fn table_name ->
        filepath = table_dump_file(root_dir, table_name) |> String.to_charlist()
        :ets.tab2file(table_name, filepath)
      end
    )

    Process.send_after(self(), :dump, dump_delay)

    {:noreply, state, :hibernate}
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
