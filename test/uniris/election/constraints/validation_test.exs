defmodule Uniris.Election.ValidationConstraintsTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  alias Uniris.Election.ValidationConstraints

  doctest ValidationConstraints

  property "validation_number return more than 3 validation nodes" do
    check all(transfers <- StreamData.list_of(StreamData.float(min: 0.0, max: 100.0))) do
      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers:
                Enum.map(transfers, fn amount ->
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: amount}
                end)
            }
          }
        }
      }

      assert ValidationConstraints.validation_number(tx) >= 3
    end
  end
end
