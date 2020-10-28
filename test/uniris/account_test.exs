defmodule Uniris.AccountTest do
  use ExUnit.Case

  alias Uniris.Account
  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  describe "get_balance/1" do
    setup do
      start_supervised!(UCOLedger)
      :ok
    end

    test "should return the sum of unspent outputs amounts" do
      UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0})
      UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Tom10", amount: 1.0})
      assert 4.0 == Account.get_balance("@Alice2")
    end

    test "should return 0 when no unspent outputs associated" do
      assert 0.0 == Account.get_balance("@Alice2")
    end

    test "should return 0 when all the unspent outputs have been spent" do
      UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0})
      UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Tom10", amount: 1.0})
      UCOLedger.spend_all_unspent_outputs("@Alice2")
      assert 0.0 == Account.get_balance("@Alice2")
    end
  end
end
