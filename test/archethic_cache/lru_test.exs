defmodule ArchethicCache.LRUTest do
  use ExUnit.Case, async: false

  @moduledoc """
  the tests are independent because the ETS table dies with the process
  """

  alias ArchethicCache.LRU

  describe "single in memory cache" do
    test "should return nil when key is not in cache" do
      {:ok, _pid} = LRU.start_link(:my_cache, 10 * 1024)

      assert nil == LRU.get(:my_cache, :key1)
    end

    test "should cache any term" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)

      LRU.put(:my_cache, :key1, 1)
      LRU.put(:my_cache, :key2, :atom)
      LRU.put(:my_cache, :key3, %{a: 1})
      LRU.put(:my_cache, {1, 2}, "binary")

      # This get_state is used to wait for all messages in the GenServer to be processed
      :sys.get_state(pid)

      assert 1 == LRU.get(:my_cache, :key1)
      assert :atom == LRU.get(:my_cache, :key2)
      assert %{a: 1} == LRU.get(:my_cache, :key3)
      assert "binary" == LRU.get(:my_cache, {1, 2})
    end

    test "should be able to replace a value" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)

      LRU.put(:my_cache, :key1, "value1a")
      LRU.put(:my_cache, :key1, "value1b")

      :sys.get_state(pid)

      assert "value1b" == LRU.get(:my_cache, :key1)
    end

    test "should evict some cached values when there is not enough space available" do
      binary = get_a_binary_of_bytes(200)

      {:ok, pid} = LRU.start_link(:my_cache, 500)

      LRU.put(:my_cache, :key1, binary)
      LRU.put(:my_cache, :key2, binary)
      LRU.put(:my_cache, :key3, get_a_binary_of_bytes(400))

      :sys.get_state(pid)

      assert nil == LRU.get(:my_cache, :key1)
      assert nil == LRU.get(:my_cache, :key2)
    end

    test "should evict the LRU" do
      binary = get_a_binary_of_bytes(200)

      {:ok, pid} = LRU.start_link(:my_cache, 500)

      LRU.put(:my_cache, :key1, binary)
      LRU.put(:my_cache, :key2, binary)

      :sys.get_state(pid)

      LRU.get(:my_cache, :key1)
      LRU.put(:my_cache, :key3, binary)

      :sys.get_state(pid)

      assert ^binary = LRU.get(:my_cache, :key1)
      assert nil == LRU.get(:my_cache, :key2)
    end

    test "should not cache a binary bigger than cache size" do
      binary = get_a_binary_of_bytes(500)

      {:ok, pid} = LRU.start_link(:my_cache, 200)

      assert :ok == LRU.put(:my_cache, :key1, binary)

      :sys.get_state(pid)

      assert nil == LRU.get(:my_cache, :key1)
    end

    test "should remove all when purged" do
      binary = get_a_binary_of_bytes(100)

      {:ok, _pid} = LRU.start_link(:my_cache, 500)

      LRU.put(:my_cache, :key1, binary)
      LRU.put(:my_cache, :key2, binary)
      LRU.purge(:my_cache)
      assert nil == LRU.get(:my_cache, :key1)
      assert nil == LRU.get(:my_cache, :key2)
    end
  end

  describe "multiple in memory caches" do
    test "should not conflict each other" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)
      assert {:error, _} = LRU.start_link(:my_cache, 10 * 1024)

      {:ok, pid2} = LRU.start_link(:my_cache2, 10 * 1024)
      LRU.put(:my_cache, :key1, "value1a")
      LRU.put(:my_cache2, :key1, "value1b")

      :sys.get_state(pid)
      :sys.get_state(pid2)

      assert "value1a" == LRU.get(:my_cache, :key1)
      assert "value1b" == LRU.get(:my_cache2, :key1)
    end
  end

  defp get_a_binary_of_bytes(bytes) do
    get_a_binary_of_bytes(bytes, <<>>)
  end

  defp get_a_binary_of_bytes(0, acc), do: acc

  defp get_a_binary_of_bytes(bytes, acc) do
    get_a_binary_of_bytes(bytes - 1, <<0::8, acc::binary>>)
  end
end
