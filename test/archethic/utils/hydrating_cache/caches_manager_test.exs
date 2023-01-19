defmodule HydratingCacheTest do
  alias Archethic.Utils.HydratingCache
  alias Archethic.Utils.HydratingCache.CachesManager
  use ExUnit.Case
  require Logger

  test "starting service from manager returns value once first hydrating have been done" do
    CachesManager.new_service_async("test_services", [
      {:key1, __MODULE__, :waiting_function, [4000], 6000},
      {:key2, __MODULE__, :waiting_function, [2000], 6000},
      {:key3, __MODULE__, :waiting_function, [4000], 6000}
    ])

    assert HydratingCache.get(
             :"Elixir.Archethic.Utils.HydratingCache.test_services",
             "key2",
             3000
           ) == {:ok, 1}
  end

  def waiting_function(delay \\ 1000) do
    :timer.sleep(delay)
    {:ok, 1}
  end
end
