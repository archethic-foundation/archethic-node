defmodule ArchethicCache.LRUTest do
  use ExUnit.Case, async: false

  @moduledoc """
  the tests are independent because the ETS table dies with the process
  """

  alias ArchethicCache.LRU

  describe "single in memory cache" do
    test "should return nil when key is not in cache" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)

      assert nil == LRU.get(pid, :key1)
    end

    test "should cache any term" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)

      LRU.put(pid, :key1, 1)
      LRU.put(pid, :key2, :atom)
      LRU.put(pid, :key3, %{a: 1})
      LRU.put(pid, {1, 2}, "binary")

      assert 1 == LRU.get(pid, :key1)
      assert :atom == LRU.get(pid, :key2)
      assert %{a: 1} == LRU.get(pid, :key3)
      assert "binary" == LRU.get(pid, {1, 2})
    end

    test "should be able to replace a value" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)

      LRU.put(pid, :key1, "value1a")
      LRU.put(pid, :key1, "value1b")

      assert "value1b" == LRU.get(pid, :key1)
    end

    test "should evict some cached values when there is not enough space available" do
      binary = get_a_binary_of_bytes(200)

      {:ok, pid} = LRU.start_link(:my_cache, 500)

      LRU.put(pid, :key1, binary)
      LRU.put(pid, :key2, binary)
      LRU.put(pid, :key3, get_a_binary_of_bytes(400))

      assert nil == LRU.get(pid, :key1)
      assert nil == LRU.get(pid, :key2)
    end

    test "should evict the LRU" do
      binary = get_a_binary_of_bytes(200)

      {:ok, pid} = LRU.start_link(:my_cache, 500)

      LRU.put(pid, :key1, binary)
      LRU.put(pid, :key2, binary)
      LRU.get(pid, :key1)
      LRU.put(pid, :key3, binary)

      assert ^binary = LRU.get(pid, :key1)
      assert nil == LRU.get(pid, :key2)
    end

    test "should not cache a binary bigger than cache size" do
      binary = get_a_binary_of_bytes(500)

      {:ok, pid} = LRU.start_link(:my_cache, 200)

      assert false == LRU.put(pid, :key1, binary)
      assert nil == LRU.get(pid, :key1)
    end

    test "should remove all when purged" do
      binary = get_a_binary_of_bytes(100)

      {:ok, pid} = LRU.start_link(:my_cache, 500)

      LRU.put(pid, :key1, binary)
      LRU.put(pid, :key2, binary)
      LRU.purge(pid)
      assert nil == LRU.get(pid, :key1)
      assert nil == LRU.get(pid, :key2)
    end
  end

  describe "multiple in memory caches" do
    test "should not conflict each other" do
      {:ok, pid} = LRU.start_link(:my_cache, 10 * 1024)
      assert {:error, _} = LRU.start_link(:my_cache, 10 * 1024)

      {:ok, pid2} = LRU.start_link(:my_cache2, 10 * 1024)
      LRU.put(pid, :key1, "value1a")
      LRU.put(pid2, :key1, "value1b")

      assert "value1a" == LRU.get(pid, :key1)
      assert "value1b" == LRU.get(pid2, :key1)
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
