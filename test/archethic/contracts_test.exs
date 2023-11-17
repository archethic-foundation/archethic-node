defmodule Archethic.ContractsTest do
  use ArchethicCase

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.ActionWithoutTransaction
  alias Archethic.Contracts.Contract.ConditionAccepted
  alias Archethic.Contracts.Contract.ConditionRejected
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Contract.State
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  @moduletag capture_log: true

  doctest Contracts

  describe "execute_condition/5 (inherit)" do
    test "should return Rejected when the inherit constraints literal values are not respected" do
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

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [
            %Transfer{
              to:
                <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                  130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
              amount: 20
            }
          ]
        }
      }

      next_tx = ContractFactory.create_next_contract_tx(contract_tx, ledger: ledger)

      assert %ConditionRejected{} =
               Contracts.execute_condition(
                 :inherit,
                 Contract.from_transaction!(contract_tx),
                 next_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Rejected when the inherit constraints execution return false" do
      code = """
      condition inherit: [
        content: regex_match?(\"hello\")
      ]

      condition transaction: []

      actions triggered_by: transaction do
        set_content "hello"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(contract_tx, content: "hola")

      assert %ConditionRejected{} =
               Contracts.execute_condition(
                 :inherit,
                 Contract.from_transaction!(contract_tx),
                 next_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Accepted when the inherit constraints matches the next transaction" do
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

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      ledger = %Ledger{
        uco: %UCOLedger{transfers: [%Transfer{to: address, amount: 1_000_000_000}]}
      }

      next_tx =
        ContractFactory.create_next_contract_tx(contract_tx,
          ledger: ledger,
          content: "hello",
          type: :transfer
        )

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 :inherit,
                 Contract.from_transaction!(contract_tx),
                 next_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Accepted when the inherit constraint match and when no trigger is specified" do
      code = """
      @version 1
      condition inherit: [
        content: "hello"
      ]
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(contract_tx, content: "hello")

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 :inherit,
                 Contract.from_transaction!(contract_tx),
                 next_tx,
                 nil,
                 DateTime.utc_now()
               )
    end
  end

  describe "execute_condition/5 (transaction)" do
    test "should return Accepted if condition is empty" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx = TransactionFactory.create_valid_transaction([])

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Accepted if condition is true" do
      code = """
        @version 1
        condition triggered_by: transaction, as: [
          type: "transfer"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx = TransactionFactory.create_valid_transaction([])

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Accepted if condition is true based on state" do
      code = """
        @version 1
        condition triggered_by: transaction, as: [
          type: State.get("key") == "value"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      encoded_state = State.serialize(%{"key" => "value"})

      # some ucos are necessary for ContractFactory.create_valid_contract_tx
      uco_utxo = %UnspentOutput{
        amount: 200_000_000,
        from: ArchethicCase.random_address(),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      contract_tx =
        ContractFactory.create_valid_contract_tx(code, state: encoded_state, inputs: [uco_utxo])

      trigger_tx = TransactionFactory.create_valid_transaction([])

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Rejected if condition is falsy" do
      code = """
        @version 1
        condition triggered_by: transaction, as: [
          type: "data"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx = TransactionFactory.create_valid_transaction([])

      assert %ConditionRejected{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Error if condition execution raise an error" do
      code = """
        @version 1
        condition triggered_by: transaction, as: [
          type: 1 + "one"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx = TransactionFactory.create_valid_transaction([])

      assert %Failure{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
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

      condition triggered_by: transaction, as: [
          content: check_content()
      ]
      actions triggered_by: transaction do
        Contract.set_content "hello world"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
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

      condition triggered_by: transaction, as: [
          content: check_content()
      ]
      actions triggered_by: transaction do
        Contract.set_content "hello world"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "I'm a content")

      assert %ConditionRejected{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
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

      condition triggered_by: transaction, as: [
          content: check_content()
      ]
      actions triggered_by: transaction do
        Contract.set_content "tresor found"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "tresor")

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 nil,
                 DateTime.utc_now()
               )
    end
  end

  describe "execute_condition/4 (oracle)" do
    test "should return Accepted if condition is empty" do
      code = """
        @version 1
        condition triggered_by: oracle, as: []

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      oracle_tx = TransactionFactory.create_valid_transaction([], type: :oracle)

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 :oracle,
                 Contract.from_transaction!(contract_tx),
                 oracle_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Accepted if condition is true" do
      code = """
        @version 1
        condition triggered_by: oracle, as: [
          content: "{}"
        ]

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      oracle_tx = TransactionFactory.create_valid_transaction([], type: :oracle, content: "{}")

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 :oracle,
                 Contract.from_transaction!(contract_tx),
                 oracle_tx,
                 nil,
                 DateTime.utc_now()
               )
    end

    test "should return Rejected if condition is falsy" do
      code = """
        @version 1
        condition triggered_by: oracle, as: [
          content: "{}"
        ]

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      oracle_tx = TransactionFactory.create_valid_transaction([], type: :oracle, content: "")

      assert %ConditionRejected{} =
               Contracts.execute_condition(
                 :oracle,
                 Contract.from_transaction!(contract_tx),
                 oracle_tx,
                 nil,
                 DateTime.utc_now()
               )
    end
  end

  describe "execute_condition/5 (transaction named action)" do
    test "should return Accepted if condition is empty" do
      code = """
        @version 1
        condition triggered_by: transaction, on: vote(candidate), as: []

        actions triggered_by: transaction, on: vote(person) do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx = TransactionFactory.create_valid_transaction([])

      recipient = %Recipient{address: contract_tx.address, action: "vote", args: ["Juliette"]}
      condition_key = Contract.get_trigger_for_recipient(recipient)

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 condition_key,
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 recipient,
                 DateTime.utc_now()
               )
    end

    test "should return Accepted if condition is true" do
      code = """
      @version 1
      condition triggered_by: transaction, on: vote(candidate), as: [
        content: "fabulous chimpanzee"
      ]

      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content "hello"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          content: "fabulous chimpanzee"
        )

      recipient = %Recipient{address: contract_tx.address, action: "vote", args: ["Jules"]}
      condition_key = Contract.get_trigger_for_recipient(recipient)

      assert %ConditionAccepted{} =
               Contracts.execute_condition(
                 condition_key,
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 recipient,
                 DateTime.utc_now()
               )
    end

    test "should return Rejected if condition is false" do
      code = """
      @version 1
      condition triggered_by: transaction, on: vote(candidate), as: [
        content: "immaterial mynah bird"
      ]

      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content "hello"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          content: "cylindrical reindeer"
        )

      recipient = %Recipient{address: contract_tx.address, action: "vote", args: ["Jules"]}
      condition_key = Contract.get_trigger_for_recipient(recipient)

      assert %ConditionRejected{} =
               Contracts.execute_condition(
                 condition_key,
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 recipient,
                 DateTime.utc_now()
               )
    end
  end

  describe "execute_trigger" do
    test "should return the proper line in case of error" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          div_by_zero()
        end

        export fun div_by_zero() do
          1 / 0
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert %Failure{user_friendly_error: "division_by_zero - L8"} =
               Contracts.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 nil
               )
    end

    test "should fail if the state is too big" do
      code = ~S"""
        @version 1
        actions triggered_by: datetime, at: 0 do
          str = ""
          for i in 0..26214 do
            str = "#{str}0000000000"
          end
          State.set("key", str)
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert %Failure{
               user_friendly_error: "Execution was successful but the state exceed the threshold"
             } =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 nil
               )
    end

    test "should return Success if the state changed" do
      code = ~S"""
        @version 1
        actions triggered_by: datetime, at: 0 do
          State.set("key", "value")
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert %ActionWithTransaction{} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 nil
               )

      code = ~S"""
        @version 1
        actions triggered_by: datetime, at: 0 do
          State.delete("key")
        end

      """

      encoded_state = State.serialize(%{"key" => "value"})
      contract_tx = ContractFactory.create_valid_contract_tx(code, state: encoded_state)

      assert %ActionWithTransaction{} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 nil
               )
    end

    test "should return NoOp if the state did not changed" do
      code = ~S"""
        @version 1
        actions triggered_by: datetime, at: 0 do
          State.set("key", "value")
        end

      """

      encoded_state = State.serialize(%{"key" => "value"})
      contract_tx = ContractFactory.create_valid_contract_tx(code, state: encoded_state)

      assert %ActionWithoutTransaction{} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 nil
               )
    end

    test "should return NoOp if there is no state" do
      code = ~S"""
        @version 1
        actions triggered_by: datetime, at: 0 do
          a = 1
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      encoded_state = State.serialize(%{"key" => "value"})

      contract_tx_with_state =
        ContractFactory.create_valid_contract_tx(code, state: encoded_state)

      assert %ActionWithoutTransaction{} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 nil
               )

      assert %ActionWithoutTransaction{} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx_with_state),
                 nil,
                 nil
               )
    end
  end

  describe "execute_function/3" do
    test "should return an error if the function takes too much time" do
      code = ~S"""
      @version 1
      export fun meaning_of_life() do
        42
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      contract = Contract.from_transaction!(contract_tx)

      # add a sleep to the AST
      contract_with_sleep =
        update_in(
          contract,
          [Access.key!(:functions), Access.key!({"meaning_of_life", 0}), Access.key!(:ast)],
          fn ast_fun ->
            quote do
              Process.sleep(5_000)
              unquote(ast_fun)
            end
          end
        )

      assert {:error, %Failure{user_friendly_error: "Function timed-out"}} =
               Contracts.execute_function(contract_with_sleep, "meaning_of_life", [])
    end

    test "should be able to read the state" do
      code = ~S"""
      @version 1
      export fun meaning_of_life() do
        State.get("key")
      end
      """

      # some ucos are necessary for ContractFactory.create_valid_contract_tx
      uco_utxo = %UnspentOutput{
        amount: 200_000_000,
        from: ArchethicCase.random_address(),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      encoded_state = State.serialize(%{"key" => 42})

      contract_tx =
        ContractFactory.create_valid_contract_tx(code, inputs: [uco_utxo], state: encoded_state)

      contract = Contract.from_transaction!(contract_tx)

      assert {:ok, 42, _} =
               Contracts.execute_function(
                 contract,
                 "meaning_of_life",
                 []
               )
    end
  end
end
