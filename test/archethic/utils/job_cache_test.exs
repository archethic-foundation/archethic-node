defmodule Archethic.Utils.JobCacheTest do
  use ExUnit.Case

  alias Archethic.Utils.JobCache

  doctest JobCache

  test "should exit if no process" do
    pid = spawn(fn -> :ok end)
    assert {:normal, _} = catch_exit(JobCache.get!(pid))
  end

  test "should not immediately start the job by default" do
    :persistent_term.put(:value, 1)

    {:ok, pid} = JobCache.start_link(function: fn -> :persistent_term.get(:value) end)

    :persistent_term.put(:value, 2)

    assert 2 = JobCache.get!(pid)
  end

  test "should immediately start the job if :immediate flag is passed " do
    :persistent_term.put(:value, 1)

    {:ok, pid} =
      JobCache.start_link(immediate: true, function: fn -> :persistent_term.get(:value) end)

    :persistent_term.put(:value, 2)

    assert 1 = JobCache.get!(pid)
  end

  test "should be able to start when using get! if there is no process yet" do
    :persistent_term.put(:value, 1)

    assert 1 = JobCache.get!(:name, function: fn -> :persistent_term.get(:value) end)
    assert 1 = JobCache.get!({:some, :key}, function: fn -> :persistent_term.get(:value) end)

    :persistent_term.put(:value, 2)

    assert 1 = JobCache.get!(:name)
    assert 1 = JobCache.get!({:some, :key})
  end
end
