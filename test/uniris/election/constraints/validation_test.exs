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
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })
    end)
  end

  property "validation_number return more than 3 validation nodes and less than 200 validation nodes" do
    check all(
      transfers <- StreamData.list_of(StreamData.float(min: 0.0, max: 10_000_000_000.0)),
      nb_authorized_node <- StreamData.positive_integer()
    ) do
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

      min = ValidationConstraints.min_validation_nodes(nb_authorized_node)

      nb_validations = ValidationConstraints.validation_number(tx, nb_authorized_node)
      assert nb_validations >= min and nb_validations <= 200
    end
  end

  describe "validation_number/2" do
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

      assert 3 == ValidationConstraints.validation_number(tx, 10)
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

      assert 6 == ValidationConstraints.validation_number(tx, 10)

      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [%Transfer{to: "@Alice2", amount: 1000}]
            }
          }
        }
      }

      assert 9 == ValidationConstraints.validation_number(tx, 10)
    end
  end
end
