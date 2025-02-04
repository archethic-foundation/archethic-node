defmodule Archethic.Governance.Pools.MemTableLoaderTest do
  use ExUnit.Case

  alias Archethic.Governance.Pools.MemTable
  alias Archethic.Governance.Pools.MemTableLoader

  alias Archethic.TransactionChain.Transaction

  setup do
    start_supervised!(MemTable)

    :ok
  end

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  describe "start_link/1" do
    test "should load technical council members from transaction code proposals" do
      MockDB
      |> expect(:list_transactions_by_type, fn _, _ ->
        [
          %Transaction{
            type: :code_proposal,
            previous_public_key: "Alice2"
          },
          %Transaction{
            type: :code_proposal,
            previous_public_key: "Alice1"
          },
          %Transaction{
            type: :code_proposal,
            previous_public_key: "Alice0"
          }
        ]
      end)
      |> stub(:get_first_public_key, fn _ -> "Alice0" end)

      assert {:ok, _} = MemTableLoader.start_link()
      assert [{"Alice0", 3}] = MemTable.list_pool_members(:technical_council)
    end
  end
end
