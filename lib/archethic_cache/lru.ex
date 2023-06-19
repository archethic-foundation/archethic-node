defmodule ArchethicCache.LRU do
  @moduledoc """
  A cache that stores the values in an ETS table.
  There are hooks available to be able to add effects (ex: write to disk).

  It keeps track of the order and bytes in the genserver state.
  The `bytes_used` are tracked in here because if we just monitor ETS table size, we would not be able to have a disk cache.
  The `keys` are used to determine the Least Recent Used (first is the most recent used, last is the least recent used).

  We do not store the values directly in ETS but we insert a pair {size, value} instead.
  Because size can be modified with the hooks
  (ex: For LRUDisk, we discard the value from the ETS table, but still want to know the size written to disk)
  """
  use GenServer
  @vsn Mix.Project.config()[:version]

  @spec start_link(GenServer.name(), non_neg_integer(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def start_link(name, max_bytes, opts \\ []) do
    GenServer.start_link(__MODULE__, [name, max_bytes, opts], name: name)
  end

  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(server, key, value) do
    GenServer.cast(server, {:put, key, value})
  end

  @spec get(GenServer.name(), term()) :: nil | term()
  def get(server_name, key) do
    case :ets.lookup(server_name, key) do
      [{^key, {_size, value}}] ->
        GenServer.cast(server_name, {:move_front, key})
        get_fn = :persistent_term.get(server_name)
        get_fn.(key, value)

      [] ->
        nil
    end
  rescue
    _ -> nil
  end

  @spec purge(GenServer.server()) :: :ok
  def purge(server) do
    GenServer.call(server, :purge)
  end

  def init([name, max_bytes, opts]) do
    table = :ets.new(name, [:set, :named_table, {:read_concurrency, true}])

    :persistent_term.put(name, Keyword.get(opts, :get_fn, fn _key, value -> value end))

    {:ok,
     %{
       table: table,
       bytes_max: max_bytes,
       bytes_used: 0,
       keys: [],
       put_fn: Keyword.get(opts, :put_fn, fn _key, value -> value end),
       evict_fn: Keyword.get(opts, :evict_fn, fn _key, _value -> :ok end)
     }}
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

  def handle_call(:purge, _from, state = %{table: table, evict_fn: evict_fn}) do
    # we call the evict_fn to be able to clean effects (ex: file written to disk)
    :ets.foldr(
      fn {key, {_size, value}}, acc ->
        evict_fn.(key, value)
        acc + 1
      end,
      0,
      table
    )

    :ets.delete_all_objects(table)
    {:reply, :ok, %{state | keys: [], bytes_used: 0}}
  end

  def handle_cast({:move_front, key}, state = %{keys: keys}) do
    {:noreply, %{state | keys: keys |> move_front(key)}}
  end

  def handle_cast(
        {:put, key, value},
        state = %{table: table, bytes_max: bytes_max, put_fn: put_fn, evict_fn: evict_fn}
      ) do
    size = :erlang.external_size(value)

    if size > bytes_max do
      {:noreply, state}
    else
      # maybe evict some keys to make space
      state =
        evict_until(state, fn %{bytes_used: bytes_used, bytes_max: bytes_max} ->
          bytes_used + size <= bytes_max
        end)

      case :ets.lookup(table, key) do
        [] ->
          value_to_store = put_fn.(key, value)

          :ets.insert(table, {key, {size, value_to_store}})

          new_state = %{
            state
            | keys: [key | state.keys],
              bytes_used: state.bytes_used + size
          }

          {:noreply, new_state}

        [{^key, {old_size, old_value}}] ->
          # this is a replacement, we need to evict to update the bytes_used
          evict_fn.(key, old_value)
          value_to_store = put_fn.(key, value)

          :ets.insert(table, {key, {size, value_to_store}})

          new_state = %{
            state
            | keys: state.keys |> move_front(key),
              bytes_used: state.bytes_used + size - old_size
          }

          {:noreply, new_state}
      end
    end
  end

  defp evict_until(
         state = %{keys: keys},
         predicate
       ) do
    # we reverse the keys here so we don't need to reverse them in a loop
    state = %{state | keys: Enum.reverse(keys)}
    new_state = do_evict_until(state, predicate)
    %{new_state | keys: Enum.reverse(new_state.keys)}
  end

  defp do_evict_until(
         state = %{
           table: table,
           keys: reversed_keys,
           evict_fn: evict_fn,
           bytes_used: bytes_used
         },
         predicate
       ) do
    if predicate.(state) do
      state
    else
      case reversed_keys do
        [] ->
          state

        [oldest_key | rest] ->
          [{_, {size, oldest_value}}] = :ets.take(table, oldest_key)
          evict_fn.(oldest_key, oldest_value)

          do_evict_until(
            %{
              state
              | bytes_used: bytes_used - size,
                keys: rest
            },
            predicate
          )
      end
    end
  end

  defp move_front(list, item) do
    [item | List.delete(list, item)]
  end
end
