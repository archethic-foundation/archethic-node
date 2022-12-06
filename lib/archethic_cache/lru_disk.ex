defmodule ArchethicCache.LRUDisk do
  @moduledoc """
  Wraps the LRU genserver and adds hooks to write / read from disk.
  The value is always a binary.
  """
  alias ArchethicCache.LRU

  require Logger

  @spec start_link(GenServer.name(), non_neg_integer(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def start_link(name, max_bytes, cache_dir) do
    cache_dir = Path.join(cache_dir, "#{name}")
    :ok = reset_directory(cache_dir)

    LRU.start_link(name, max_bytes,
      put_fn: fn key, value ->
        # retry to create the dir everytime in case someones delete it
        File.mkdir_p!(cache_dir)

        # write to disk
        File.write!(key_to_path(cache_dir, key), value, [:exclusive, :binary])

        # return value to store in memory and size
        # we use the size as value so it's available in the evict fn without doing a File.stat
        size = byte_size(value)
        {size, size}
      end,
      get_fn: fn key, _size ->
        # called only if the key is already in LRU's ETS table
        case File.read(key_to_path(cache_dir, key)) do
          {:ok, bin} ->
            bin

          {:error, _} ->
            nil
        end
      end,
      evict_fn: fn key, size ->
        case File.rm(key_to_path(cache_dir, key)) do
          :ok ->
            :ok

          {:error, _} ->
            :ok
        end

        # return size deleted
        size
      end
    )
  end

  @spec put(GenServer.server(), term(), binary()) :: boolean()
  defdelegate put(pid, key, value), to: LRU, as: :put

  @spec get(GenServer.server(), term()) :: nil | binary()
  defdelegate get(pid, key), to: LRU, as: :get

  @spec purge(GenServer.server()) :: :ok
  defdelegate purge(pid), to: LRU, as: :purge

  defp reset_directory(dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
  end

  defp key_to_path(cache_dir, key) do
    # DISCUSS: use a proper hash function
    # DISCUSS: this is flat and not site/file
    hash = Base.encode64(:erlang.term_to_binary(key))
    Path.join(cache_dir, hash)
  end
end
