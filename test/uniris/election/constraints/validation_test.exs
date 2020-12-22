defmodule Uniris.Election.ValidationConstraintsTest do
  use UnirisCase
  use ExUnitProperties

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  alias Uniris.Election.ValidationConstraints

  doctest ValidationConstraints

  setup do
    Enum.each(1..50, fn _ ->
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })
    end)
  end

  property "validation_number return more than 3 validation nodes and less than 200 validation nodes" do
    check all(transfers <- StreamData.list_of(StreamData.float(min: 0.0, max: 10_000_000_000.0))) do
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

      assert ValidationConstraints.validation_number(tx) >= 3 and
               ValidationConstraints.validation_number(tx) <= 200
    end
  end

  describe "validation_number/1" do
    test "should return the minimum before 10 UCO" do
      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [%Transfer{to: "@Alice2", amount: 0.05}]
            }
          }
        }
      }

      assert 3 == ValidationConstraints.validation_number(tx)
    end

    test "should return a number based on the UCO value" do
      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [%Transfer{to: "@Alice2", amount: 200}]
            }
          }
        }
      }

      assert 6 == ValidationConstraints.validation_number(tx)

      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [%Transfer{to: "@Alice2", amount: 1000}]
            }
          }
        }
      }

      assert 9 == ValidationConstraints.validation_number(tx)
    end
  end
end
