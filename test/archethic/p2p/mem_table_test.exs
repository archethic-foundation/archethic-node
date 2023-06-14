defmodule Archethic.P2P.MemTableTest do
  # use ExUnit.Case
  use ArchethicCase

  alias Archethic.P2P.MemTable
  alias Archethic.P2P.Node

  doctest MemTable

  test "code_change" do
    values =
      {"key1", "key2", {127, 0, 0, 1}, 3000, 4000, "AFZ", "AAA", 0.9, <<1::1, 1::1>>,
       ~U[2020-10-22 23:19:45.797109Z], :tcp, "reward_address", "last_address", "origin_key",
       true, ~U[2020-10-22 23:19:45.797109Z], true, ~U[2020-10-22 23:19:45.797109Z]}

    :ets.insert(:archethic_node_discovery, values)
    assert {:ok, %{}} = MemTable.code_change("1.1.1", %{}, nil)

    assert [
             {"key1", "key2", {127, 0, 0, 1}, 3000, 4000, "AFZ", "AAA", 0.9,
              ~U[2020-10-22 23:19:45.797109Z], :tcp, "reward_address", "last_address",
              "origin_key", true, ~U[2020-10-22 23:19:45.797109Z], true,
              ~U[2020-10-22 23:19:45.797109Z]}
           ] = :ets.lookup(:archethic_node_discovery, "key1")
  end
end
