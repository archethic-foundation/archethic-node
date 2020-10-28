defmodule Uniris.Governance.Pools.MemTableLoaderTest do
  use ExUnit.Case

  alias Uniris.Crypto

  alias Uniris.Governance.Pools.MemTable
  alias Uniris.Governance.Pools.MemTableLoader

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.MemTables.KOLedger
  alias Uniris.TransactionChain.Transaction

  setup do
    start_supervised!(ChainLookup)
    start_supervised!(KOLedger)
    start_supervised!(MemTable)

    :ok
  end

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  describe "start_link/1" do
    test "should load technical council members from transaction code proposals" do
      ChainLookup.add_transaction_by_type(
        Crypto.hash("Alice3"),
        :code_proposal,
        DateTime.utc_now() |> DateTime.add(2)
      )

      ChainLookup.add_transaction_by_type(
        Crypto.hash("Alice2"),
        :code_proposal,
        DateTime.utc_now() |> DateTime.add(1)
      )

      ChainLookup.add_transaction_by_type(
        Crypto.hash("Alice1"),
        :code_proposal,
        DateTime.utc_now()
      )

      ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")

      MockDB
      |> stub(:get_transaction, fn address, _ ->
        cond do
          address == Crypto.hash("Alice3") ->
            {:ok, %Transaction{type: :code_proposal, previous_public_key: "Alice2"}}

          address == Crypto.hash("Alice2") ->
            {:ok, %Transaction{type: :code_proposal, previous_public_key: "Alice1"}}

          address == Crypto.hash("Alice1") ->
            {:ok, %Transaction{type: :code_proposal, previous_public_key: "Alice0"}}
        end
      end)

      assert {:ok, _} = MemTableLoader.start_link()
      assert [{"Alice0", 3}] = MemTable.list_pool_members(:technical_council)
    end
  end
end
