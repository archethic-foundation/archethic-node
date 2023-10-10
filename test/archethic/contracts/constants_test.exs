defmodule Archethic.Contracts.ConstantsTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Contracts.Constants

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
        |> Constants.from_transaction()

      assert %{"type" => "transfer"} = constant
    end

    test "should return both uco transfer & movements" do
      uco_movement_address = random_address()
      uco_movement_address_hex = Base.encode16(uco_movement_address)
      uco_movement_amount = 2

      token_movement_address = random_address()
      token_movement_address_hex = Base.encode16(token_movement_address)
      token_movement_amount = 7

      uco_input_address = random_address()
      uco_input_address_hex = Base.encode16(uco_input_address)
      uco_input_amount = 5

      token_address = random_address()
      token_address_hex = Base.encode16(token_address)
      token_input_address = random_address()
      token_input_address_hex = Base.encode16(token_input_address)
      token_input_amount = 8

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UcoTransfer{
              to: uco_input_address,
              amount: Utils.to_bigint(uco_input_amount)
            }
          ]
        },
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              to: token_input_address,
              amount: Utils.to_bigint(token_input_amount),
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
            amount: Utils.to_bigint(uco_movement_amount),
            type: :UCO
          },
          %TransactionMovement{
            to: token_movement_address,
            amount: Utils.to_bigint(token_movement_amount),
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
        |> Constants.from_transaction()

      assert %{
               "uco_movements" => uco_movements,
               "token_movements" => token_movements,
               "uco_transfers" => uco_transfers,
               "token_transfers" => token_transfers
             } = constant

      assert uco_movement_amount == uco_movements[uco_movement_address_hex]
      assert uco_input_amount == uco_transfers[uco_input_address_hex]

      [token_movement_at_address] = token_movements[token_movement_address_hex]
      assert token_movement_amount == token_movement_at_address["amount"]
      assert token_address_hex == token_movement_at_address["token_address"]
      assert 2 == token_movement_at_address["token_id"]

      [token_transfers_at_address] = token_transfers[token_input_address_hex]
      assert token_input_amount == token_transfers_at_address["amount"]
      assert token_address_hex == token_transfers_at_address["token_address"]
      assert 1 == token_transfers_at_address["token_id"]
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

      secret = :crypto.strong_rand_bytes(32)
      public = random_public_key()
      encrypted_key = :crypto.strong_rand_bytes(32)

      ownership = %Ownership{secret: secret, authorized_keys: %{public => encrypted_key}}

      ownership_hex = %{
        "secret" => Base.encode16(secret),
        "authorized_keys" => %{Base.encode16(public) => Base.encode16(encrypted_key)}
      }

      contract_tx = ContractFactory.create_valid_contract_tx(code, ownerships: [ownership])

      assert length(contract_tx.data.ownerships) == 2

      assert %{"ownerships" => [^ownership_hex]} =
               Constants.from_contract_transaction(contract_tx)
    end
  end
end
