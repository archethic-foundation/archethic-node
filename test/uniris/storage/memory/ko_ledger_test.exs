defmodule Uniris.Storage.Memory.KOLedgerTest do
  use ExUnit.Case

  alias Uniris.Storage.Memory.KOLedger

  alias Uniris.Transaction
  alias Uniris.Transaction.CrossValidationStamp
  alias Uniris.Transaction.ValidationStamp

  test "has_transaction?/1 should return true when the transaction is ko" do
    KOLedger.start_link([])

    KOLedger.add_transaction(%Transaction{
      address: "@Alice2",
      validation_stamp: %ValidationStamp{},
      cross_validation_stamps: []
    })

    assert true == KOLedger.has_transaction?("@Alice2")
  end

  test "remove_transaction/1 should remove the transaction from the ko ledger" do
    KOLedger.start_link([])

    KOLedger.add_transaction(%Transaction{
      address: "@Alice2",
      validation_stamp: %ValidationStamp{},
      cross_validation_stamps: []
    })

    KOLedger.remove_transaction("@Alice2")

    assert false == KOLedger.has_transaction?("@Alice2")
  end

  test "get_details/1 should get the details of the KO transaction" do
    KOLedger.start_link([])

    KOLedger.add_transaction(%Transaction{
      address: "@Alice2",
      validation_stamp: %ValidationStamp{},
      cross_validation_stamps: [
        %CrossValidationStamp{
          inconsistencies: [:proof_of_work]
        }
      ]
    })

    assert {%ValidationStamp{}, [:proof_of_work], []} = KOLedger.get_details("@Alice2")
  end
end
