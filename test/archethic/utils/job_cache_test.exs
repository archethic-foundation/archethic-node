defmodule Archethic.Utils.JobCacheTest do
  use ExUnit.Case

  alias Archethic.Utils.JobCache

  doctest JobCache

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
end
