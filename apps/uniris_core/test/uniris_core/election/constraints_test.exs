defmodule UnirisCore.Election.ConstraintsTest do
  use UnirisCoreCase
  use ExUnitProperties

  alias UnirisCore.Election.Constraints
  alias UnirisCore.P2P.Node

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger

  property "validation_number return more than 3 validation nodes" do
    check all(transfers <- StreamData.list_of(StreamData.float(min: 0.0, max: 100.0))) do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers:
                  Enum.map(transfers, fn amount ->
                    %Transfer{to: :crypto.strong_rand_bytes(32), amount: amount}
                  end)
              }
            }
          },
          "seed",
          0
        )

      assert Constraints.validation_number(tx) >= 3
    end
  end

  describe "validation_number/1" do
    test "should return min validations when less than 10 uco transfered" do
      assert 3 ==
               Constraints.validation_number(
                 Transaction.new(:transfer, %TransactionData{}, "seed", 0)
               )
    end

    test "should return 6 for 100 uco" do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 100.0}
                ]
              }
            }
          },
          "seed",
          0
        )

      assert 6 == Constraints.validation_number(tx)
    end
  end

  property "number_replicas/2 should return the total number nodes before 143 nodes" do
    check all(
            average_availabilities <-
              StreamData.list_of(StreamData.float(min: 0.0, max: 1.0),
                min_length: 1,
                max_length: 143
              )
          ) do
      assert Enum.map(average_availabilities, fn avg ->
               %Node{
                 first_public_key: :crypto.strong_rand_bytes(32),
                 last_public_key: :crypto.strong_rand_bytes(32),
                 ip: {127, 0, 0, 1},
                 port: 3000,
                 average_availability: avg
               }
             end)
             |> Constraints.number_replicas() == length(average_availabilities)
    end
  end

  property "number_replicas/2 should return the less than total number nodes after 143 nodes" do
    check all(
            average_availabilities <-
              StreamData.list_of(StreamData.float(min: 0.0, max: 1.0), min_length: 143)
          ) do
      assert Enum.map(average_availabilities, fn avg ->
               %Node{
                 first_public_key: :crypto.strong_rand_bytes(32),
                 last_public_key: :crypto.strong_rand_bytes(32),
                 ip: {127, 0, 0, 1},
                 port: 3000,
                 average_availability: avg
               }
             end)
             |> Constraints.number_replicas() <= 143
    end
  end
end
