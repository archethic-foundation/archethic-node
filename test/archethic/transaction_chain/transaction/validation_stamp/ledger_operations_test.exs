defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperationsTest do
  alias Archethic.Reward.MemTables.RewardTokens

  alias Archethic.TransactionFactory
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  use ArchethicCase
  import ArchethicCase

  doctest LedgerOperations

  setup do
    start_supervised!(RewardTokens)
    :ok
  end

  describe "serialization" do
    test "should be able to serialize and deserialize" do
      ops = %LedgerOperations{
        fee: 10_000_000,
        transaction_movements: [
          %TransactionMovement{
            to:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 102_000_000,
            type: :UCO
          }
        ],
        unspent_outputs: [
          %UnspentOutput{
            from:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 200_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 07:27:22.815Z]
          }
        ]
      }

      for version <- 1..current_protocol_version() do
        assert {^ops, <<>>} =
                 LedgerOperations.serialize(ops, version)
                 |> LedgerOperations.deserialize(version)
      end
    end
  end

  describe("get_utxos_from_transaction/2") do
    test "should return empty list for non token/mint_reward transactiosn" do
      types = Archethic.TransactionChain.Transaction.types() -- [:node, :mint_reward]

      Enum.each(types, fn t ->
        assert [] =
                 LedgerOperations.get_utxos_from_transaction(
                   TransactionFactory.create_valid_transaction([], type: t),
                   DateTime.utc_now()
                 )
      end)
    end

    test "should return empty list if content is invalid" do
      assert [] =
               LedgerOperations.get_utxos_from_transaction(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: "not a json"
                 ),
                 DateTime.utc_now()
               )

      assert [] =
               LedgerOperations.get_utxos_from_transaction(
                 TransactionFactory.create_valid_transaction([], type: :token, content: "{}"),
                 DateTime.utc_now()
               )
    end
  end

  describe("get_utxos_from_transaction/2 with a token resupply transaction") do
    test "should return a utxo" do
      token_address = random_address()
      token_address_hex = token_address |> Base.encode16()
      now = DateTime.utc_now()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
          "token_reference": "#{token_address_hex}",
          "supply": 1000000
          }
          """
        )

      tx_address = tx.address

      assert [
               %UnspentOutput{
                 amount: 1_000_000,
                 from: ^tx_address,
                 type: {:token, ^token_address, 0},
                 timestamp: ^now
               }
             ] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end

    test "should return an empty list if invalid tx" do
      now = DateTime.utc_now()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
          "token_reference": "nonhexadecimal",
          "supply": 1000000
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
          "token_reference": {"foo": "bar"},
          "supply": 1000000
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)

      token_address = random_address()
      token_address_hex = token_address |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
          "token_reference": "#{token_address_hex}",
          "supply": "hello"
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end
  end

  describe("get_utxos_from_transaction/2 with a token creation transaction") do
    test "should return a utxo (for fungible)" do
      now = DateTime.utc_now()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 1000000000,
            "type": "fungible",
            "decimals": 8,
            "name": "NAME OF MY TOKEN",
            "symbol": "MTK"
          }
          """
        )

      tx_address = tx.address

      assert [
               %UnspentOutput{
                 amount: 1_000_000_000,
                 from: ^tx_address,
                 type: {:token, ^tx_address, 0},
                 timestamp: ^now
               }
             ] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end

    test "should return a utxo (for non-fungible)" do
      now = DateTime.utc_now()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 100000000,
            "type": "non-fungible",
            "name": "My NFT",
            "symbol": "MNFT",
            "properties": {
               "image": "base64 of the image",
               "description": "This is a NFT with an image"
            }
          }
          """
        )

      tx_address = tx.address

      assert [
               %UnspentOutput{
                 amount: 100_000_000,
                 from: ^tx_address,
                 type: {:token, ^tx_address, 1},
                 timestamp: ^now
               }
             ] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end

    test "should return a utxo (for non-fungible collection)" do
      now = DateTime.utc_now()

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
            ]
          }
          """
        )

      tx_address = tx.address

      assert [
               %UnspentOutput{
                 amount: 100_000_000,
                 from: ^tx_address,
                 type: {:token, ^tx_address, 1},
                 timestamp: ^now
               },
               %UnspentOutput{
                 amount: 100_000_000,
                 from: ^tx_address,
                 type: {:token, ^tx_address, 2},
                 timestamp: ^now
               },
               %UnspentOutput{
                 amount: 100_000_000,
                 from: ^tx_address,
                 type: {:token, ^tx_address, 3},
                 timestamp: ^now
               }
             ] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end

    test "should return an empty list if amount is incorrect (for non-fungible)" do
      now = DateTime.utc_now()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 1,
            "type": "non-fungible",
            "name": "My NFT",
            "symbol": "MNFT",
            "properties": {
               "image": "base64 of the image",
               "description": "This is a NFT with an image"
            }
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end

    test "should return an empty list if invalid tx" do
      now = DateTime.utc_now()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
          "supply": "foo"
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
          "supply": 100000000
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "type": "fungible"
          }
          """
        )

      assert [] = LedgerOperations.get_utxos_from_transaction(tx, now)
    end
  end

  describe "consume_inputs/4" do
    test "When a single unspent output is sufficient to satisfy the transaction movements" do
      assert %LedgerOperations{
               fee: 40_000_000,
               unspent_outputs: [
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 703_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 }
               ]
             } =
               LedgerOperations.consume_inputs(
                 %LedgerOperations{fee: 40_000_000},
                 "@Alice2",
                 [
                   %UnspentOutput{
                     from: "@Bob3",
                     amount: 2_000_000_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
                   %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
                 ],
                 [],
                 nil,
                 ~U[2022-10-10 10:44:38.983Z]
               )
               |> elem(1)
    end

    test "When multiple little unspent output are sufficient to satisfy the transaction movements" do
      assert %LedgerOperations{
               fee: 40_000_000,
               unspent_outputs: [
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 1_103_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 }
               ]
             } =
               %LedgerOperations{fee: 40_000_000}
               |> LedgerOperations.consume_inputs(
                 "@Alice2",
                 [
                   %UnspentOutput{from: "@Bob3", amount: 500_000_000, type: :UCO},
                   %UnspentOutput{from: "@Tom4", amount: 700_000_000, type: :UCO},
                   %UnspentOutput{from: "@Christina", amount: 400_000_000, type: :UCO},
                   %UnspentOutput{from: "@Hugo", amount: 800_000_000, type: :UCO}
                 ],
                 [
                   %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
                   %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
                 ],
                 [],
                 nil,
                 ~U[2022-10-10 10:44:38.983Z]
               )
               |> elem(1)
    end

    test "When using Token unspent outputs are sufficient to satisfy the transaction movements" do
      assert %LedgerOperations{
               fee: 40_000_000,
               unspent_outputs: [
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 160_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 },
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 200_000_000,
                   type: {:token, "@CharlieToken", 0},
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 }
               ]
             } =
               %LedgerOperations{fee: 40_000_000}
               |> LedgerOperations.consume_inputs(
                 "@Alice2",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 200_000_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   },
                   %UnspentOutput{
                     from: "@Bob3",
                     amount: 1_200_000_000,
                     type: {:token, "@CharlieToken", 0},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@Bob4",
                     amount: 1_000_000_000,
                     type: {:token, "@CharlieToken", 0}
                   }
                 ],
                 [],
                 nil,
                 ~U[2022-10-10 10:44:38.983Z]
               )
               |> elem(1)
    end

    test "When multiple Token unspent outputs are sufficient to satisfy the transaction movements" do
      assert %LedgerOperations{
               fee: 40_000_000,
               unspent_outputs: [
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 160_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 },
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 900_000_000,
                   type: {:token, "@CharlieToken", 0},
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 }
               ]
             } =
               %LedgerOperations{fee: 40_000_000}
               |> LedgerOperations.consume_inputs(
                 "@Alice2",
                 [
                   %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
                   %UnspentOutput{
                     from: "@Bob3",
                     amount: 500_000_000,
                     type: {:token, "@CharlieToken", 0}
                   },
                   %UnspentOutput{
                     from: "@Hugo5",
                     amount: 700_000_000,
                     type: {:token, "@CharlieToken", 0}
                   },
                   %UnspentOutput{
                     from: "@Tom1",
                     amount: 700_000_000,
                     type: {:token, "@CharlieToken", 0}
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@Bob4",
                     amount: 1_000_000_000,
                     type: {:token, "@CharlieToken", 0}
                   }
                 ],
                 [],
                 nil,
                 ~U[2022-10-10 10:44:38.983Z]
               )
               |> elem(1)
    end

    test "When non-fungible tokens are used as input but want to consume only a single input" do
      assert %LedgerOperations{
               fee: 40_000_000,
               unspent_outputs: [
                 %UnspentOutput{
                   from: "@Alice2",
                   amount: 160_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-10 10:44:38.983Z]
                 },
                 %UnspentOutput{
                   from: "@CharlieToken",
                   amount: 100_000_000,
                   type: {:token, "@CharlieToken", 1},
                   timestamp: ~U[2022-10-09 08:39:10.463Z]
                 },
                 %UnspentOutput{
                   from: "@CharlieToken",
                   amount: 100_000_000,
                   type: {:token, "@CharlieToken", 3},
                   timestamp: ~U[2022-10-09 08:39:10.463Z]
                 }
               ]
             } =
               %LedgerOperations{fee: 40_000_000}
               |> LedgerOperations.consume_inputs(
                 "@Alice2",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 200_000_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   },
                   %UnspentOutput{
                     from: "@CharlieToken",
                     amount: 100_000_000,
                     type: {:token, "@CharlieToken", 1},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   },
                   %UnspentOutput{
                     from: "@CharlieToken",
                     amount: 100_000_000,
                     type: {:token, "@CharlieToken", 2},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   },
                   %UnspentOutput{
                     from: "@CharlieToken",
                     amount: 100_000_000,
                     type: {:token, "@CharlieToken", 3},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@Bob4",
                     amount: 100_000_000,
                     type: {:token, "@CharlieToken", 2}
                   }
                 ],
                 [],
                 nil,
                 ~U[2022-10-10 10:44:38.983Z]
               )
               |> elem(1)
    end

    test "should return insufficient funds when not enough uco" do
      ops = %LedgerOperations{fee: 1_000}

      assert {false, _} =
               LedgerOperations.consume_inputs(ops, "@Alice", [], [], [], nil, DateTime.utc_now())
    end

    test "should return insufficient funds when not enough tokens" do
      ops = %LedgerOperations{fee: 1_000}

      assert {false, _} =
               LedgerOperations.consume_inputs(
                 ops,
                 "@Alice",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 1_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@JeanClaude",
                     amount: 100_000_000,
                     type: {:token, "@CharlieToken", 0}
                   }
                 ],
                 [],
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should be able to pay with the minted fungible tokens" do
      now = DateTime.utc_now()

      ops = %LedgerOperations{fee: 1_000}

      assert {true, ops_result} =
               LedgerOperations.consume_inputs(
                 ops,
                 "@Alice",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 1_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@JeanClaude",
                     amount: 50_000_000,
                     type: {:token, "@Token", 0}
                   }
                 ],
                 [
                   %UnspentOutput{
                     from: "@Bob",
                     amount: 100_000_000,
                     type: {:token, "@Token", 0},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 nil,
                 now
               )

      assert [
               # I don't like utxo of amount=0
               %UnspentOutput{
                 from: "@Alice",
                 amount: 0,
                 type: :UCO,
                 timestamp: ^now
               },
               %UnspentOutput{
                 from: "@Alice",
                 amount: 50_000_000,
                 type: {:token, "@Token", 0},
                 timestamp: ^now
               }
             ] = ops_result.unspent_outputs
    end

    test "should be able to pay with the minted non-fungible tokens" do
      now = DateTime.utc_now()

      ops = %LedgerOperations{fee: 1_000}

      assert {true, ops_result} =
               LedgerOperations.consume_inputs(
                 ops,
                 "@Alice",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 1_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@JeanClaude",
                     amount: 100_000_000,
                     type: {:token, "@Token", 1}
                   }
                 ],
                 [
                   %UnspentOutput{
                     from: "@Bob",
                     amount: 100_000_000,
                     type: {:token, "@Token", 1},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 nil,
                 now
               )

      assert [
               # I don't like utxo of amount=0
               %UnspentOutput{
                 from: "@Alice",
                 amount: 0,
                 type: :UCO,
                 timestamp: ^now
               }
             ] = ops_result.unspent_outputs
    end

    test "should be able to pay with the minted non-fungible tokens (collection)" do
      now = DateTime.utc_now()

      ops = %LedgerOperations{fee: 1_000}

      assert {true, ops_result} =
               LedgerOperations.consume_inputs(
                 ops,
                 "@Alice",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 1_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@JeanClaude",
                     amount: 100_000_000,
                     type: {:token, "@Token", 2}
                   }
                 ],
                 [
                   %UnspentOutput{
                     from: "@Bob",
                     amount: 100_000_000,
                     type: {:token, "@Token", 1},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   },
                   %UnspentOutput{
                     from: "@Bob",
                     amount: 100_000_000,
                     type: {:token, "@Token", 2},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 nil,
                 now
               )

      assert [
               # I don't like utxo of amount=0
               %UnspentOutput{
                 from: "@Alice",
                 amount: 0,
                 type: :UCO,
                 timestamp: ^now
               },
               %UnspentOutput{
                 from: "@Bob",
                 amount: 100_000_000,
                 type: {:token, "@Token", 1},
                 timestamp: ~U[2022-10-09 08:39:10.463Z]
               }
             ] = ops_result.unspent_outputs
    end

    test "should not be able to pay with the same non-fungible token twice" do
      now = DateTime.utc_now()

      ops = %LedgerOperations{fee: 1_000}

      assert {false, _} =
               LedgerOperations.consume_inputs(
                 ops,
                 "@Alice",
                 [
                   %UnspentOutput{
                     from: "@Charlie1",
                     amount: 1_000,
                     type: :UCO,
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 [
                   %TransactionMovement{
                     to: "@JeanClaude",
                     amount: 100_000_000,
                     type: {:token, "@Token", 1}
                   },
                   %TransactionMovement{
                     to: "@JeanBob",
                     amount: 100_000_000,
                     type: {:token, "@Token", 1}
                   }
                 ],
                 [
                   %UnspentOutput{
                     from: "@Bob",
                     amount: 100_000_000,
                     type: {:token, "@Token", 1},
                     timestamp: ~U[2022-10-09 08:39:10.463Z]
                   }
                 ],
                 nil,
                 now
               )
    end

    test "should merge two similar tokens and update the from & timestamp" do
      transaction_address = random_address()
      transaction_timestamp = DateTime.utc_now()

      from = random_address()
      token_address = random_address()
      old_timestamp = ~U[2023-11-09 10:39:10Z]

      assert {true,
              %LedgerOperations{
                unspent_outputs: [
                  %UnspentOutput{
                    from: ^transaction_address,
                    amount: 160_000_000,
                    type: :UCO,
                    timestamp: ^transaction_timestamp
                  },
                  %UnspentOutput{
                    from: ^transaction_address,
                    amount: 200_000_000,
                    type: {:token, ^token_address, 0},
                    timestamp: ^transaction_timestamp
                  }
                ],
                fee: 40_000_000
              }} =
               LedgerOperations.consume_inputs(
                 %LedgerOperations{fee: 40_000_000},
                 transaction_address,
                 [
                   %UnspentOutput{
                     from: from,
                     amount: 200_000_000,
                     type: :UCO,
                     timestamp: old_timestamp
                   },
                   %UnspentOutput{
                     from: from,
                     amount: 100_000_000,
                     type: {:token, token_address, 0},
                     timestamp: old_timestamp
                   },
                   %UnspentOutput{
                     from: from,
                     amount: 100_000_000,
                     type: {:token, token_address, 0},
                     timestamp: old_timestamp
                   }
                 ],
                 [],
                 [],
                 nil,
                 transaction_timestamp
               )
    end
  end

  describe "build_resoved_movements/3" do
    test "should resolve, convert reward and aggregate movements" do
      address1 = random_address()
      address2 = random_address()

      resolved_address1 = random_address()
      resolved_address2 = random_address()

      token_address = random_address()
      reward_token_address = random_address()

      resolved_addresses = %{address1 => resolved_address1, address2 => resolved_address2}

      RewardTokens.add_reward_token_address(reward_token_address)

      movement = [
        %TransactionMovement{to: address1, amount: 10, type: :UCO},
        %TransactionMovement{to: address1, amount: 10, type: {:token, token_address, 0}},
        %TransactionMovement{to: address1, amount: 40, type: {:token, token_address, 0}},
        %TransactionMovement{to: address2, amount: 30, type: {:token, reward_token_address, 0}},
        %TransactionMovement{to: address1, amount: 50, type: {:token, reward_token_address, 0}}
      ]

      expected_resolved_movement = [
        %TransactionMovement{to: resolved_address1, amount: 60, type: :UCO},
        %TransactionMovement{to: resolved_address1, amount: 50, type: {:token, token_address, 0}},
        %TransactionMovement{to: resolved_address2, amount: 30, type: :UCO}
      ]

      assert %LedgerOperations{transaction_movements: resolved_movements} =
               LedgerOperations.build_resolved_movements(
                 %LedgerOperations{},
                 movement,
                 resolved_addresses,
                 :transfer
               )

      # Order does not matters
      assert length(expected_resolved_movement) == length(resolved_movements)
      assert Enum.all?(expected_resolved_movement, &Enum.member?(resolved_movements, &1))
    end
  end
end
