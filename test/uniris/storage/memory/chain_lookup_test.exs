defmodule Uniris.Storage.Memory.ChainLookupTest do
  use ExUnit.Case

  import Mox

  setup :set_mox_global

  alias Uniris.Crypto

  alias Uniris.Storage.Memory.ChainLookup

  alias Uniris.Transaction

  test "start_link/1 should create ets table and load transaction in memory" do
    tx1_addr = Crypto.hash("Alice1")
    tx2_addr = Crypto.hash("Alice2")

    MockStorage
    |> stub(:list_transaction_chains_info, fn ->
      [
        {tx2_addr, 2},
        {tx1_addr, 1}
      ]
    end)
    |> stub(:get_transaction_chain, fn address, _fields ->
      cond do
        address == tx2_addr ->
          [
            %Transaction{
              address: tx2_addr,
              previous_public_key: "Alice1"
            },
            %Transaction{
              address: tx1_addr,
              previous_public_key: "Alice0"
            }
          ]

        address == tx1_addr ->
          [
            %Transaction{
              address: tx1_addr,
              previous_public_key: "Alice0"
            }
          ]

        true ->
          raise "Unexpected address"
      end
    end)

    {:ok, _} = ChainLookup.start_link([])

    [{_, 2}] = :ets.lookup(:uniris_chain_lookup, {:chain_length, tx2_addr})
    [{_, 1}] = :ets.lookup(:uniris_chain_lookup, {:chain_length, tx1_addr})

    assert [{tx1_addr, tx2_addr}] = :ets.lookup(:uniris_chain_lookup, tx1_addr)
  end

  test "reverse_link/2 should create a link to traverse chain from previous public keys" do
    MockStorage
    |> stub(:list_transaction_chains_info, fn -> [] end)

    ChainLookup.start_link([])

    tx0_addr = Crypto.hash("Alice0")
    tx1_addr = Crypto.hash("Alice1")
    tx2_addr = Crypto.hash("Alice2")

    ChainLookup.reverse_link(tx2_addr, "Alice1")
    ChainLookup.reverse_link(tx1_addr, "Alice0")

    assert {:ok, tx2_addr} = ChainLookup.get_last_transaction_address(tx0_addr)
  end
end
