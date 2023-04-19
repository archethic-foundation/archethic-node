defmodule Archethic.UtilsTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.P2P.Node
  alias Archethic.Utils

  doctest Utils

  setup do
    Registry.start_link(keys: :unique, name: Archethic.AtMostOnceConcurrentlyRegistry)
    :ok
  end

  test "run_at_most_once_concurrently/2 should run a function only once" do
    me = self()

    Task.async_stream(0..10, fn _ ->
      Utils.run_at_most_once_concurrently(
        fn _ ->
          send(me, :bar)

          # simulate some execution time
          Process.sleep(10)
        end,
        :foo
      )
    end)
    |> Stream.run()

    assert_receive :bar, 100
    refute_receive :bar, 100
  end
end
