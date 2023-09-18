defmodule ArchethicCache.LRU do
  @moduledoc """
  A cache that stores the values in an ETS table using Last Recent Used strategy (first is the most recent used, last is the least recent used)

  There are hooks available to be able to add effects (ex: write to disk)
  - put_fn/2: function called once a data is inserted. For LRUDisk, we discard the value from the ETS table, but still want to know the size written to disk)
  - get_fn/2: function called after the value from the ETS cache is retrieved.
  - evict_fn/2: function called once a data is removed from the ETS cache

  This cache keeps track of the order and bytes in the ets tables:
  - cache table containing all the entries along with the value size and key index
  - cache index table containing all the index pointing to the keys. The IDs are then sorted to ease the eviction policy.
  - cache statistics table containing all the information about the cache size, capacity, and indexing.
  """

  use GenServer

  @vsn 2

  @spec start_link(GenServer.name(), cache_capacity :: non_neg_integer(), opts :: keyword()) ::
          GenServer.on_start()
  def start_link(name, capacity, opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.merge(opts, name: name, capacity: capacity),
      name: name
    )
  end

  @doc """
  Retrieve value in the cache from the given key

  Because the cache uses LRU, the key is moved on the most recent used key to cycle and re-prioritize cache entry
  """
  @spec get(GenServer.name(), term()) :: nil | term()
  def get(cache_name, key) do
    case cache_entry(cache_name, key) do
      nil ->
        nil

      entry = %{value: value} ->
        GenServer.cast(cache_name, {:update_recent, key, entry})

        get_fn = :persistent_term.get(cache_name)
        get_fn.(key, value)
    end
  rescue
    _ ->
      nil
  end

  @doc """
  Write an entry in the cache

  After writing, the LRU is updated by moving the key in the most recent used key to cycle and re-prioritize cache entry
  """
  @spec put(GenServer.server(), key :: term(), value :: term(), async? :: boolean()) :: :ok
  def put(cache_name, key, value, async? \\ true)

  def put(cache_name, key, value, true) do
    GenServer.cast(cache_name, {:put, key, value})
  end

  def put(cache_name, key, value, false) do
    GenServer.call(cache_name, {:put, key, value})
  end

  @doc false
  @spec purge(GenServer.server()) :: :ok
  def purge(cache_name) do
    GenServer.call(cache_name, :purge)
  end

  def init(opts) do
    cache_name = Keyword.fetch!(opts, :name)
    cache_capacity = Keyword.fetch!(opts, :capacity)
    new_cache(cache_name, cache_capacity)

    :persistent_term.put(cache_name, Keyword.get(opts, :get_fn, fn _key, value -> value end))

    {:ok,
     %{
       cache_name: cache_name,
       put_fn: Keyword.get(opts, :put_fn, fn _key, value -> value end),
       evict_fn: Keyword.get(opts, :evict_fn, fn _key, _value -> :ok end)
     }}
  end

  defp new_cache(cache_name, capacity) do
    :ets.new(table_name(:cache, cache_name), [:set, :public, :named_table])
    :ets.new(table_name(:cache_stats, cache_name), [:set, :named_table])
    :ets.new(table_name(:cache_index, cache_name), [:ordered_set, :named_table])

    :ets.insert(table_name(:cache_stats, cache_name), {:capacity, capacity})
    :ets.insert(table_name(:cache_stats, cache_name), {:size, 0})
    :ets.insert(table_name(:cache_stats, cache_name), {:id, 0})
  end

  def handle_cast({:update_recent, key, node}, state = %{cache_name: cache_name}) do
    update_recently_used(cache_name, key, node)
    {:noreply, state}
  end

  def handle_cast(
        {:put, key, value},
        state = %{cache_name: cache_name, put_fn: put_fn, evict_fn: evict_fn}
      ) do
    put_cache_entry(cache_name, key, value, put_fn, evict_fn)
    {:noreply, state}
  end

  def handle_call(
        {:put, key, value},
        _from,
        state = %{cache_name: cache_name, put_fn: put_fn, evict_fn: evict_fn}
      ) do
    put_cache_entry(cache_name, key, value, put_fn, evict_fn)
    {:reply, :ok, state}
  end

  def handle_call(:purge, _from, state = %{cache_name: cache_name, evict_fn: evict_fn}) do
    # we call the evict_fn to be able to clean effects (ex: file written to disk)
    :ets.foldr(
      fn {key, %{value: value}}, acc ->
        evict_fn.(key, value)
        acc + 1
      end,
      0,
      table_name(:cache, cache_name)
    )

    :ets.delete_all_objects(table_name(:cache, cache_name))

    :ets.insert(table_name(:cache_stats, cache_name), {:id, 0})
    :ets.insert(table_name(:cache_stats, cache_name), {:size, 0})

    :ets.delete_all_objects(table_name(:cache_index, cache_name))

    {:reply, :ok, state}
  end

  def code_change(_, state, _) do
    # As we use hot reload we need to update also the lambda function stored in
    # permanent term or GenServer state. But as we don't know the function definition
    # we kill the current GenServer and the Supervisor will restart it with the new function
    # using the last version
    me = self()
    Task.start(fn -> Process.exit(me, :kill) end)
    {:ok, state}
  end

  defp table_name(table, table_name) do
    :"#{table}_#{table_name}"
  end

  defp put_cache_entry(cache_name, key, value, put_fn, evict_fn) do
    value_size = :erlang.external_size(value)
    capacity = cache_capacity(cache_name)

    if value_size <= capacity do
      case cache_entry(cache_name, key) do
        nil ->
          new_entry(cache_name, key, value, value_size, capacity, put_fn, evict_fn)

        entry ->
          replace_entry(cache_name, key, value, entry, value_size, put_fn, evict_fn)
      end
    end
  end

  defp new_entry(cache_name, key, value, value_size, capacity, put_fn, evict_fn) do
    if cache_size(cache_name) + value_size >= capacity do
      evict_oldest_entry(cache_name, value_size, evict_fn)
    end

    # In the case of the disk LRU we don't want store the data in the ets table but on the disk
    # Hence the value to store will be nil
    # The LRU would serve a key holding but delegate the value retrieval to the `get_fn`
    value_to_store = put_fn.(key, value)

    id = get_index_id(cache_name)
    add_cache_index(cache_name, id, key)
    add_cache_entry(cache_name, key, %{value: value_to_store, id: id, size: value_size})

    increase_cache_size(cache_name, value_size)
  end

  defp replace_entry(
         cache_name,
         key,
         value,
         entry = %{value: old_value, size: previous_size},
         value_size,
         put_fn,
         evict_fn
       ) do
    # this is a replacement, we need to evict to update the bytes_used particularly in the case of disk LRU
    evict_fn.(key, old_value)

    # In the case of the disk LRU we don't want store the data in the ets table but on the disk
    # Hence the value to store will be nil
    # The LRU would serve a key holding but delegate the value retrieval to the `get_fn`
    value_to_store = put_fn.(key, value)

    # Update entry and move the keys in the front of the cache as the most used key
    new_entry = %{entry | value: value_to_store, size: value_size}
    add_cache_entry(cache_name, key, new_entry)
    update_recently_used(cache_name, key, new_entry)

    # Update the size used by the table
    update_cache_size(cache_name, previous_size, value_size)
  end

  defp cache_capacity(cache_name) do
    [{_, capacity}] = :ets.lookup(table_name(:cache_stats, cache_name), :capacity)
    capacity
  end

  defp cache_size(cache_name) do
    [{_, size}] = :ets.lookup(table_name(:cache_stats, cache_name), :size)
    size
  end

  defp cache_entry(cache_name, key) do
    case :ets.lookup(table_name(:cache, cache_name), key) do
      [] ->
        nil

      [{_, entry}] ->
        entry
    end
  end

  defp add_cache_entry(cache_name, key, value) do
    :ets.insert(table_name(:cache, cache_name), {key, value})
  end

  defp add_cache_index(cache_name, id, key_cache) do
    :ets.insert(table_name(:cache_index, cache_name), {id, key_cache})
  end

  defp get_index_id(cache_name) do
    :ets.update_counter(table_name(:cache_stats, cache_name), :id, {2, 1})
  end

  defp increase_cache_size(cache_name, size) do
    :ets.update_counter(
      table_name(:cache_stats, cache_name),
      :size,
      {2, size}
    )
  end

  defp update_cache_size(cache_name, previous_size, new_size) do
    :ets.update_counter(
      table_name(:cache_stats, cache_name),
      :size,
      [{2, -previous_size}, {2, new_size}]
    )
  end

  defp update_recently_used(cache_name, key, entry = %{id: previous_id}) do
    # Acquire a new id
    new_id = get_index_id(cache_name)

    # Delete previous id to priorize the new one
    delete_cache_index(cache_name, previous_id)
    add_cache_index(cache_name, new_id, key)

    # Update the node's id
    add_cache_entry(cache_name, key, %{entry | id: new_id})
  end

  defp evict_oldest_entry(cache_name, value_size, evict_fn, free_size \\ 0)

  defp evict_oldest_entry(_cache_name, value_size, _evict_fn, free_size)
       when free_size >= value_size,
       do: :ok

  defp evict_oldest_entry(cache_name, value_size, evict_fn, free_size) do
    # Get the oldest to reclaim space
    case cache_tail_key(cache_name) do
      nil ->
        :ok

      tail_key ->
        %{value: tail_value, size: reclaimed_space, id: id} = cache_entry(cache_name, tail_key)
        evict_fn.(tail_key, tail_value)

        # Free space and entries
        delete_cache_index(cache_name, id)
        delete_cache_entry(cache_name, tail_key)
        decrease_cache_size(cache_name, reclaimed_space)

        evict_oldest_entry(cache_name, value_size, evict_fn, free_size + reclaimed_space)
    end
  end

  defp cache_tail_key(cache_name) do
    case :ets.first(table_name(:cache_index, cache_name)) do
      :"$end_of_table" ->
        nil

      first_id ->
        [{_, key}] = :ets.lookup(table_name(:cache_index, cache_name), first_id)
        key
    end
  end

  defp delete_cache_index(cache_name, id) do
    :ets.delete(table_name(:cache_index, cache_name), id)
  end

  defp delete_cache_entry(cache_name, key) do
    :ets.delete(table_name(:cache, cache_name), key)
  end

  defp decrease_cache_size(cache_name, size) do
    :ets.update_counter(
      table_name(:cache_stats, cache_name),
      :size,
      {2, -size, 0, 0}
    )
  end
end
