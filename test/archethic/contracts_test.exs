defmodule Archethic.ContractsTest do
  use ArchethicCase

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  import ArchethicCase

  @moduletag capture_log: true

  doctest Contracts

  describe "valid_condition?/5 (inherit)" do
    test "should return false when the inherit constraints literal values are not respected" do
      code = """
      condition inherit: [
        uco_transfers: [%{ to: "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9", amount: 1000000000}],
        content: "hello"
      ]

      condition transaction: []

      actions triggered_by: transaction do
        add_uco_transfer to: "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9", amount: 1000000000
      end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 20.0
                }
              ]
            }
          }
        }
      }

      refute Contracts.valid_condition?(
               :inherit,
               Contract.from_transaction!(contract_tx),
               next_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return false when the inherit constraints execution return false" do
      code = """
      condition inherit: [
        content: regex_match?(\"hello\")
      ]

      condition transaction: []

      actions triggered_by: transaction do
        set_content "hello"
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "hola"
        }
      }

      refute Contracts.valid_condition?(
               :inherit,
               Contract.from_transaction!(contract_tx),
               next_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return true when the inherit constraints matches the next transaction" do
      address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition inherit: [
        content: regex_match?("hello"),
        uco_transfers: %{"#{Base.encode16(address)}" => 1000000000},
        type: transfer
      ]

      condition transaction: []

      actions triggered_by: transaction do
        add_uco_transfer to: "#{Base.encode16(address)}", amount: 1000000000
        set_content "hello"
        set_type transfer
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :transfer,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "hello",
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to: address,
                  amount: 1_000_000_000
                }
              ]
            }
          }
        }
      }

      assert Contracts.valid_condition?(
               :inherit,
               Contract.from_transaction!(contract_tx),
               next_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return true when the inherit constraint match and when no trigger is specified" do
      code = """
      condition inherit: [
        content: "hello"
      ]
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "hello"
        }
      }

      assert Contracts.valid_condition?(
               :inherit,
               Contract.from_transaction!(contract_tx),
               next_tx,
               nil,
               DateTime.utc_now()
             )
    end
  end

  describe "valid_execution?/3" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: ArchethicCase.random_public_key(),
        last_public_key: ArchethicCase.random_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      :ok
    end

    test "should return false if there is no context and there is a trigger" do
      now = ~U[2023-06-20 12:00:00Z]

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = %Transaction{
        address: random_address(),
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "wake up"
        }
      }

      refute Contracts.valid_execution?(prev_tx, next_tx, nil)
    end

    test "should return true if there is no context and there is no trigger" do
      code = """
      @version 1
      condition inherit: [ content: true ]
      """

      prev_tx = %Transaction{
        address: random_address(),
        type: :oracle,
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :oracle,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "{\"uco\":{\"eur\":0.00, \"usd\":0.00}}"
        }
      }

      assert Contracts.valid_execution?(prev_tx, next_tx, nil)
    end

    test "should return true when the transaction have been triggered by datetime and timestamp matches" do
      now = %DateTime{DateTime.utc_now() | second: 0, microsecond: {0, 0}}

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = %Transaction{
        address: random_address(),
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "wake up"
        }
      }

      contract_context = %Contract.Context{
        trigger: {:datetime, now},
        status: :tx_output,
        timestamp: now
      }

      assert Contracts.valid_execution?(prev_tx, next_tx, contract_context)
    end

    test "should return false when the transaction have been triggered by datetime but timestamp doesn't match" do
      yesterday = %DateTime{
        (DateTime.utc_now()
         |> DateTime.add(-1, :day))
        | second: 0,
          microsecond: {0, 0}
      }

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(yesterday)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "wake up"
        }
      }

      contract_context = %Contract.Context{
        trigger: {:datetime, yesterday},
        status: :tx_output,
        timestamp: DateTime.utc_now()
      }

      refute Contracts.valid_execution?(prev_tx, next_tx, contract_context)
    end

    test "should return true when the transaction have been triggered by interval and timestamp matches" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "beep"
        }
      }

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      assert Contracts.valid_execution?(prev_tx, next_tx, contract_context)
    end

    test "should return false when the transaction have been triggered by interval but timestamp doesn't match" do
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "beep"
        }
      }

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", yesterday},
        status: :tx_output,
        timestamp: DateTime.utc_now()
      }

      refute Contracts.valid_execution?(prev_tx, next_tx, contract_context)
    end

    test "should return true when the resulting transaction is the same as next_transaction" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "beep"
        }
      }

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      assert Contracts.valid_execution?(prev_tx, next_tx, contract_context)
    end

    test "should return false when the resulting transaction is the same as next_transaction" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code,
          content: "boop"
        }
      }

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      refute Contracts.valid_execution?(prev_tx, next_tx, contract_context)
    end
  end

  describe "valid_condition?/5 (transaction)" do
    test "should return true if condition is empty" do
      code = """
        @version 1
        condition transaction: []

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        type: :transfer,
        address: random_address(),
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return true if condition is true" do
      code = """
        @version 1
        condition transaction: [
          type: "transfer"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        type: :transfer,
        address: random_address(),
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return false if condition is falsy" do
      code = """
        @version 1
        condition transaction: [
          type: "data"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        type: :transfer,
        address: random_address(),
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      refute Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return false if condition execution raise an error" do
      code = """
        @version 1
        condition transaction: [
          type: 1 + "one"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        type: :transfer,
        address: random_address(),
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      refute Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should be able to use a custom function call as parameter in condition block" do
      code = """
      @version 1

      fun check_content() do
         true
      end

      condition transaction: [
          content: check_content()
      ]
      actions triggered_by: transaction do
        Contract.set_content "hello world"
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               incoming_tx,
               nil,
               DateTime.utc_now()
             )

      code = """
      @version 1

      fun check_content() do
         false
      end

      condition transaction: [
          content: check_content()
      ]
      actions triggered_by: transaction do
        Contract.set_content "hello world"
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{
          content: "I'm a content"
        },
        validation_stamp: ValidationStamp.generate_dummy()
      }

      refute Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               incoming_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should pass first parameter automatically to custom fun in condition block" do
      code = """
      @version 1

      fun check_content(content) do
         content == "tresor"
      end

      condition transaction: [
          content: check_content()
      ]
      actions triggered_by: transaction do
        Contract.set_content "tresor found"
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{
          content: "tresor"
        },
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               incoming_tx,
               nil,
               DateTime.utc_now()
             )
    end
  end

  describe "valid_condition?/4 (oracle)" do
    test "should return true if condition is empty" do
      code = """
        @version 1
        condition oracle: []

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      oracle_tx = %Transaction{
        type: :oracle,
        address: random_address(),
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               :oracle,
               Contract.from_transaction!(contract_tx),
               oracle_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return true if condition is true" do
      code = """
        @version 1
        condition oracle: [
          content: "{}"
        ]

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      oracle_tx = %Transaction{
        address: random_address(),
        type: :oracle,
        data: %TransactionData{content: "{}"},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               :oracle,
               Contract.from_transaction!(contract_tx),
               oracle_tx,
               nil,
               DateTime.utc_now()
             )
    end

    test "should return false if condition is falsy" do
      code = """
        @version 1
        condition oracle: [
          content: "{}"
        ]

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      oracle_tx = %Transaction{
        address: random_address(),
        type: :oracle,
        data: %TransactionData{content: ""},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      refute Contracts.valid_condition?(
               :oracle,
               Contract.from_transaction!(contract_tx),
               oracle_tx,
               nil,
               DateTime.utc_now()
             )
    end
  end

  describe "valid_condition?/5 (transaction named action)" do
    test "should return true if condition is empty" do
      code = """
        @version 1
        condition transaction, on: vote(candidate), as: []

        actions triggered_by: transaction, on: vote(candidate) do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        type: :transfer,
        address: random_address(),
        data: %TransactionData{},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               {:transaction, "vote", ["candidate"]},
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               %Recipient{
                 address: contract_tx.address,
                 action: "vote",
                 args: ["Juliette"]
               },
               DateTime.utc_now()
             )
    end

    test "should return true if condition is true" do
      code = """
      @version 1
      condition transaction, on: vote(candidate), as: [
        content: "fabulous chimpanzee"
      ]

      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content "hello"
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        address: random_address(),
        type: :data,
        data: %TransactionData{content: "fabulous chimpanzee"},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      assert Contracts.valid_condition?(
               {:transaction, "vote", ["candidate"]},
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               %Recipient{
                 address: contract_tx.address,
                 action: "vote",
                 args: ["Jules"]
               },
               DateTime.utc_now()
             )
    end

    test "should return false if condition is false" do
      code = """
      @version 1
      condition transaction, on: vote(candidate), as: [
        content: "immaterial mynah bird"
      ]

      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content "hello"
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: code
        }
      }

      trigger_tx = %Transaction{
        address: random_address(),
        type: :data,
        data: %TransactionData{content: "cylindrical reindeer"},
        validation_stamp: ValidationStamp.generate_dummy()
      }

      refute Contracts.valid_condition?(
               {:transaction, "vote", ["candidate"]},
               Contract.from_transaction!(contract_tx),
               trigger_tx,
               %Recipient{
                 address: contract_tx.address,
                 action: "vote",
                 args: ["Jules"]
               },
               DateTime.utc_now()
             )
    end
  end
end
