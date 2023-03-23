defmodule Archethic.UtilsTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.P2P.Node
  alias Archethic.Utils

  doctest Utils

  describe "fire_and_forget_with_timeout/2" do
    test "should kill the process if it takes too long" do
      {:ok, pid} = Utils.fire_and_forget_with_timeout(10, fn -> Process.sleep(5_000) end)
      {:ok, pid2} = Utils.fire_and_forget_with_timeout(10, {Process, :sleep, [5_000]})
      assert Process.alive?(pid)
      assert Process.alive?(pid2)
      Process.sleep(15)
      refute Process.alive?(pid)
      refute Process.alive?(pid2)
    end
  end
end
