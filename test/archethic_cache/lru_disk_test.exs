defmodule ArchethicCache.LRUDiskTest do
  use ExUnit.Case, async: false

  @moduledoc """
  the tests are independent because the ETS table dies with the process and the disk is cleared on init
  """

  @cache_dir Path.join(Archethic.Utils.mut_dir(), "aecache")

  alias ArchethicCache.LRUDisk

  describe "single disk cache" do
    test "should return nil when key is not in cache" do
      {:ok, pid} = LRUDisk.start_link(:my_cache, 10 * 1024, @cache_dir)

      assert nil == LRUDisk.get(pid, :key1)
    end

    test "should cache binaries" do
      {:ok, pid} = LRUDisk.start_link(:my_cache, 10 * 1024, @cache_dir)

      LRUDisk.put(pid, :key1, "my binary")
      LRUDisk.put(pid, :key2, "my binary2")
      LRUDisk.put(pid, :key3, "my binary3")

      assert "my binary" == LRUDisk.get(pid, :key1)
      assert "my binary2" == LRUDisk.get(pid, :key2)
      assert "my binary3" == LRUDisk.get(pid, :key3)
    end

    test "should be able to replace binaries" do
      {:ok, pid} = LRUDisk.start_link(:my_cache, 10 * 1024, @cache_dir)

      LRUDisk.put(pid, :key1, "my binary")
      LRUDisk.put(pid, :key1, "my binary2")

      assert "my binary2" == LRUDisk.get(pid, :key1)
      assert 1 == length(File.ls!(cache_dir_for_ls(:my_cache)))
    end

    test "should evict some cached values when there is not enough space available" do
      binary = get_a_binary_of_bytes(200)

      {:ok, pid} = LRUDisk.start_link(:my_cache, 500, @cache_dir)

      LRUDisk.put(pid, :key1, binary)
      LRUDisk.put(pid, :key2, binary)
      LRUDisk.put(pid, :key3, get_a_binary_of_bytes(400))

      assert nil == LRUDisk.get(pid, :key1)
      assert nil == LRUDisk.get(pid, :key2)
      assert 1 == length(File.ls!(cache_dir_for_ls(:my_cache)))
    end

    test "should evict the LRU" do
      binary = get_a_binary_of_bytes(200)

      {:ok, pid} = LRUDisk.start_link(:my_cache, 500, @cache_dir)

      LRUDisk.put(pid, :key1, binary)
      LRUDisk.put(pid, :key2, binary)
      LRUDisk.get(pid, :key1)
      LRUDisk.put(pid, :key3, binary)

      assert ^binary = LRUDisk.get(pid, :key1)
      assert ^binary = LRUDisk.get(pid, :key3)
      assert nil == LRUDisk.get(pid, :key2)
      assert 2 == length(File.ls!(cache_dir_for_ls(:my_cache)))
    end

    test "should not cache a binary bigger than cache size" do
      binary = get_a_binary_of_bytes(500)

      {:ok, pid} = LRUDisk.start_link(:my_cache, 200, @cache_dir)

      assert :ok == LRUDisk.put(pid, :key1, binary)
      assert nil == LRUDisk.get(pid, :key1)
      assert Enum.empty?(File.ls!(cache_dir_for_ls(:my_cache)))
    end

    test "should not crash if an external intervention deletes the file or folder" do
      binary = get_a_binary_of_bytes(400)

      server = :my_cache

      start_supervised!(%{
        id: ArchethicCache.LRUDisk,
        start: {ArchethicCache.LRUDisk, :start_link, [server, 500, @cache_dir]}
      })

      LRUDisk.put(server, :key1, binary)

      assert ^binary = LRUDisk.get(server, :key1)

      # example of external intervention
      File.rm_rf!(cache_dir_for_ls(server))

      # we loose the cached value
      assert nil == LRUDisk.get(server, :key1)

      pid_before_crash = Process.whereis(server)

      # capture_log is used to hide the LRU process terminating
      # because we don't want red in our logs when it's expected
      # ps: only use it with async: false
      ExUnit.CaptureLog.capture_log(fn ->
        # if we try to add new values, it will crash the LRU process (write to a non existing dir)
        # the cache is restarted from a blank state (recreate dir) by the supervisor
        # the caller will not crash (it's a genserver.cast)
        LRUDisk.put(server, :key1, binary)

        # allow some time for supervisor to restart the LRU
        Process.sleep(100)
      end)

      pid_after_crash = Process.whereis(server)
      assert Process.alive?(pid_after_crash)
      refute Process.alive?(pid_before_crash)

      # cache should automatically restart later
      LRUDisk.put(server, :key1, binary)
      assert ^binary = LRUDisk.get(server, :key1)
    end

    test "should remove when purged" do
      binary = get_a_binary_of_bytes(400)

      {:ok, pid} = LRUDisk.start_link(:my_cache, 500, @cache_dir)

      LRUDisk.put(pid, :key1, binary)
      LRUDisk.put(pid, :key2, binary)
      LRUDisk.purge(pid)
      assert nil == LRUDisk.get(pid, :key1)
      assert nil == LRUDisk.get(pid, :key2)

      assert Enum.empty?(File.ls!(cache_dir_for_ls(:my_cache)))
    end
  end

  describe "multiple disk caches" do
    test "should not conflict each other" do
      {:ok, pid} = LRUDisk.start_link(:my_cache, 10 * 1024, @cache_dir)
      assert {:error, _} = LRUDisk.start_link(:my_cache, 10 * 1024, @cache_dir)

      {:ok, pid2} = LRUDisk.start_link(:my_cache2, 10 * 1024, @cache_dir)
      LRUDisk.put(pid, :key1, "value1a")
      LRUDisk.put(pid2, :key1, "value1b")

      assert "value1a" == LRUDisk.get(pid, :key1)
      assert "value1b" == LRUDisk.get(pid2, :key1)
      assert 1 == length(File.ls!(cache_dir_for_ls(:my_cache)))
      assert 1 == length(File.ls!(cache_dir_for_ls(:my_cache2)))
    end
  end

  defp cache_dir_for_ls(name), do: Path.join(@cache_dir, "#{name}")

  defp get_a_binary_of_bytes(bytes) do
    get_a_binary_of_bytes(bytes, <<>>)
  end

  defp get_a_binary_of_bytes(0, acc), do: acc

  defp get_a_binary_of_bytes(bytes, acc) do
    get_a_binary_of_bytes(bytes - 1, <<0::8, acc::binary>>)
  end
end
