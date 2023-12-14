defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovementTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  doctest TransactionMovement

  describe "resolve_movements/2" do
    test "should resolve the movements" do
      transfer1_address = random_address()
      transfer2_address = random_address()
      transfer3_address = random_address()
      resolved1_address = random_address()
      resolved2_address = random_address()
      resolved3_address = random_address()
      token_address = random_address()

      resolved_addresses = %{
        transfer1_address => resolved1_address,
        transfer2_address => resolved2_address,
        transfer3_address => resolved3_address
      }

      assert [
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved2_address,
                 amount: 20,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved3_address,
                 amount: 30,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: {:token, ^token_address, 0}
               }
             ] =
               TransactionMovement.resolve_movements(
                 [
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer2_address,
                     amount: 20,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer3_address,
                     amount: 30,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: {:token, token_address, 0}
                   }
                 ],
                 resolved_addresses
               )
    end

    test "should resolve the movements with multiple time the same address" do
      transfer1_address = random_address()
      resolved1_address = random_address()
      token_address = random_address()

      resolved_addresses = %{
        transfer1_address => resolved1_address
      }

      assert [
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 20,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 30,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: {:token, ^token_address, 0}
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 30,
                 type: {:token, ^token_address, 0}
               }
             ] =
               TransactionMovement.resolve_movements(
                 [
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 20,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 30,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: {:token, token_address, 0}
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 30,
                     type: {:token, token_address, 0}
                   }
                 ],
                 resolved_addresses
               )
    end

    test "should drop movements without resolve address" do
      transfer1_address = random_address()
      transfer2_address = random_address()
      transfer3_address = random_address()
      token_address = random_address()

      resolved_addresses = %{}

      assert [] =
               TransactionMovement.resolve_movements(
                 [
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer2_address,
                     amount: 20,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer3_address,
                     amount: 30,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 30,
                     type: {:token, token_address, 0}
                   }
                 ],
                 resolved_addresses
               )
    end
  end
end
