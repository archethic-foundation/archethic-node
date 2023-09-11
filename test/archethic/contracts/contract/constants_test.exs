defmodule Archethic.Contracts.ContractConstantsTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Contracts.ContractConstants

  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UcoTransfer
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.Utils

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  describe "from_transaction/1" do
    test "should return a map" do
      tx = TransactionFactory.create_valid_transaction()

      constant =
        tx
        |> ContractConstants.from_transaction()

      assert %{"type" => "transfer"} = constant
    end

    test "should return both uco transfer & movements" do
      token_address = random_address()

      uco_movement_address = random_address()
      uco_movement_amount = Utils.to_bigint(2)
      token_movement_address = random_address()
      token_movement_amount = Utils.to_bigint(7)
      uco_input_address = random_address()
      uco_input_amount = Utils.to_bigint(5)
      token_input_address = random_address()
      token_input_amount = Utils.to_bigint(8)

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UcoTransfer{
              to: uco_input_address,
              amount: uco_input_amount
            }
          ]
        },
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              to: token_input_address,
              amount: token_input_amount,
              token_address: token_address,
              token_id: 1
            }
          ]
        }
      }

      ledger_op = %LedgerOperations{
        fee: Utils.to_bigint(1.337),
        transaction_movements: [
          %TransactionMovement{
            to: uco_movement_address,
            amount: uco_movement_amount,
            type: :UCO
          },
          %TransactionMovement{
            to: token_movement_address,
            amount: token_movement_amount,
            type: {:token, token_address, 2}
          }
        ]
      }

      # This won't produce a cryptographically valid transaction
      # because we override some fields after the validation stamp has been set.
      # But it's fine for testing purposes
      constant =
        TransactionFactory.create_valid_transaction([], ledger: ledger)
        |> put_in([Access.key!(:validation_stamp), Access.key!(:ledger_operations)], ledger_op)
        |> ContractConstants.from_transaction()

      assert %{
               "uco_movements" => uco_movements,
               "token_movements" => token_movements,
               "uco_transfers" => uco_transfers,
               "token_transfers" => token_transfers
             } = constant

      assert ^uco_movement_amount = uco_movements[uco_movement_address]
      assert ^uco_input_amount = uco_transfers[uco_input_address]

      [token_movement_at_address] = token_movements[token_movement_address]
      assert ^token_movement_amount = token_movement_at_address["amount"]
      assert ^token_address = token_movement_at_address["token_address"]
      assert 2 = token_movement_at_address["token_id"]

      [token_transfers_at_address] = token_transfers[token_input_address]
      assert ^token_input_amount = token_transfers_at_address["amount"]
      assert ^token_address = token_transfers_at_address["token_address"]
      assert 1 = token_transfers_at_address["token_id"]
    end
  end

  describe "from_contract/1" do
    test "should remove the contract seed ownership" do
      code = """
      @version 1
      actions triggered_by: datetime, at: 1676332800 do
        Contract.set_content "ok"
      end
      """

      ownerships = [
        %Ownership{
          secret: "secret",
          authorized_keys: %{random_public_key() => :crypto.strong_rand_bytes(32)}
        }
      ]

      contract_tx = ContractFactory.create_valid_contract_tx(code, ownerships: ownerships)

      assert length(contract_tx.data.ownerships) == 2

      assert %{"ownerships" => ^ownerships} = ContractConstants.from_contract(contract_tx)
    end
  end
end
