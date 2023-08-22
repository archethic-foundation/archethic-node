defmodule Archethic.TransactionChain.TransactionTest do
  @moduledoc false
  use ArchethicCase, async: false

  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.TransactionFactory

  doctest Archethic.TransactionChain.Transaction

  describe "new/2" do
    test "with type ':node' create a new transaction using the node keys" do
      tx = Transaction.new(:node, %TransactionData{})

      assert tx.address == Crypto.derive_address(Crypto.next_node_public_key())
      assert tx.previous_public_key == Crypto.last_node_public_key()

      assert Crypto.verify?(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.origin_node_public_key()
             )
    end

    test "with type ':node_shared_secrets' create a new transaction using the node shared secrets keys" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      assert tx.address ==
               Crypto.derive_address(
                 Crypto.node_shared_secrets_public_key(
                   Crypto.number_of_node_shared_secrets_keys() + 1
                 )
               )

      key_index = Crypto.number_of_node_shared_secrets_keys()
      assert tx.previous_public_key == Crypto.node_shared_secrets_public_key(key_index)

      assert Crypto.verify?(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.origin_node_public_key()
             )
    end
  end

  test "new/4 should create transaction with specific seed and index" do
    tx = Transaction.new(:node, %TransactionData{}, "seed", 0)
    tx2 = Transaction.new(:node, %TransactionData{}, "seed", 1)

    assert Crypto.derive_address(tx2.previous_public_key) == tx.address
  end

  describe "valid_stamps_signature?/2" do
    test "should return false if validation stamp signature is invalid" do
      tx = TransactionFactory.create_transaction_with_invalid_validation_stamp_signature()

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return true if validation stamp signature is good" do
      tx = TransactionFactory.create_valid_transaction()

      keys = [[Crypto.first_node_public_key()]]

      assert Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return true if validation stamp signature is good having a list of public keys" do
      tx = TransactionFactory.create_valid_transaction()

      keys = [
        [random_public_key(), Crypto.first_node_public_key()],
        [random_public_key(), random_public_key()]
      ]

      assert Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return false if multiple cross validation stamps are from the same node" do
      tx = TransactionFactory.create_valid_transaction()
      cross_stamps = tx.cross_validation_stamps

      tx = %Transaction{tx | cross_validation_stamps: cross_stamps ++ cross_stamps}

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return false if cross validation stamps are invalid" do
      tx = TransactionFactory.create_valid_transaction()

      cross_stamps =
        tx.cross_validation_stamps
        |> Enum.map(fn cross_stamp ->
          %{cross_stamp | signature: :crypto.strong_rand_bytes(32)}
        end)

      tx = %Transaction{tx | cross_validation_stamps: cross_stamps}

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end
  end

  describe "get_movements/1 ledgers" do
    test "should return the ledgers" do
      assert [
               %TransactionMovement{
                 to: "@Alice1",
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: "@Alice1",
                 amount: 3,
                 type: {:token, "@BobToken", 0}
               }
             ] =
               Transaction.get_movements(%Transaction{
                 data: %TransactionData{
                   ledger: %Ledger{
                     uco: %UCOLedger{
                       transfers: [
                         %UCOLedger.Transfer{to: "@Alice1", amount: 10}
                       ]
                     },
                     token: %TokenLedger{
                       transfers: [
                         %TokenLedger.Transfer{
                           to: "@Alice1",
                           amount: 3,
                           token_address: "@BobToken",
                           token_id: 0
                         }
                       ]
                     }
                   }
                 }
               })
    end
  end

  describe "get_movements/1 token resupply transaction" do
    test "should return the movements for a fungible token" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()
      recipient2 = random_address()
      recipient2_hex = recipient2 |> Base.encode16()
      token = random_address()
      token_hex = token |> Base.encode16()

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 1_000,
                 type: {:token, ^token, 0}
               },
               %TransactionMovement{
                 to: ^recipient2,
                 amount: 2_000,
                 type: {:token, ^token, 0}
               }
             ] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                     "token_reference": "#{token_hex}",
                     "supply": 1000000,
                     "recipients": [{
                       "to": "#{recipient1_hex}",
                       "amount": 1000
                     },
                     {
                      "to": "#{recipient2_hex}",
                      "amount": 2000
                     }]
                   }
                   """
                 )
               )
    end

    test "should return an empty list if no recipients" do
      token = random_address()
      token_hex = token |> Base.encode16()

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                     "token_reference": "#{token_hex}",
                     "supply": 1000000
                   }
                   """
                 )
               )
    end

    test "should return an empty list if invalid transaction" do
      token = random_address()
      token_hex = token |> Base.encode16()
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                    "token_reference": "#{token_hex}"
                   }
                   """
                 )
               )

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                    "token_reference": "not an hexadecimal",
                    "supply": 100000000,
                    "recipients": [{
                      "to": "#{recipient1_hex}",
                      "amount": 1000
                    }]
                   }
                   """
                 )
               )

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                     "supply": 1000000
                   }
                   """
                 )
               )
    end
  end

  describe "get_movements/1 token creation transaction" do
    test "should return the movements for a fungible token" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()
      recipient2 = random_address()
      recipient2_hex = recipient2 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
           "aeip": [2, 8, 19],
           "supply": 300000000,
           "type": "fungible",
           "name": "My token",
           "symbol": "MTK",
           "properties": {},
           "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 1000
            },
            {
             "to": "#{recipient2_hex}",
             "amount": 2000
            }]
          }
          """
        )

      tx_address = tx.address

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 1_000,
                 type: {:token, ^tx_address, 0}
               },
               %TransactionMovement{
                 to: ^recipient2,
                 amount: 2_000,
                 type: {:token, ^tx_address, 0}
               }
             ] = Transaction.get_movements(tx)
    end

    test "should return the movements for a non-fungible token" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 100000000,
            "type": "non-fungible",
            "name": "My NFT",
            "symbol": "MNFT",
            "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 100000000,
              "token_id": 1
            }]
          }
          """
        )

      tx_address = tx.address

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 100_000_000,
                 type: {:token, ^tx_address, 1}
               }
             ] = Transaction.get_movements(tx)
    end

    test "should return the movements for a non-fungible token (collection)" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 300000000,
            "name": "My NFT",
            "type": "non-fungible",
            "symbol": "MNFT",
            "properties": {
               "description": "this property is for all NFT"
            },
            "collection": [
               { "image": "link of the 1st NFT image" },
               { "image": "link of the 2nd NFT image" },
               {
                  "image": "link of the 3rd NFT image",
                  "other_property": "other value"
               }
            ],
            "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 100000000,
              "token_id": 3
            }]
          }
          """
        )

      tx_address = tx.address

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 100_000_000,
                 type: {:token, ^tx_address, 3}
               }
             ] = Transaction.get_movements(tx)
    end

    test "should return an empty list when trying to send a fraction of a non-fungible" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 100000000,
            "type": "non-fungible",
            "name": "My NFT",
            "symbol": "MNFT",
            "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 1
            }]
          }
          """
        )

      assert [] = Transaction.get_movements(tx)
    end
  end
end
