defmodule Archethic.Contracts.Interpreter.Library.Common.TimeTest do
  use ArchethicCase

  alias Archethic.ContractFactory
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.ConditionRejected
  alias Archethic.Contracts.Interpreter.Library.Common.Time
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionFactory

  doctest Time

  describe "now/0" do
    test "should work in the action block" do
      datetime = ~U[1970-01-01 00:00:00Z]
      timestamp = DateTime.to_unix(datetime)

      code = ~s"""
      @version 1

      condition inherit: [
        content: true
      ]

      actions triggered_by: datetime, at: #{timestamp} do
        Contract.set_content Time.now()
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, %ActionWithTransaction{next_tx: next_tx}} =
               Contracts.execute_trigger(
                 {:datetime, datetime},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 nil,
                 time_now: datetime
               )

      assert %Transaction{data: %TransactionData{content: content}} = next_tx
      assert String.to_integer(content) == timestamp
    end

    test "should run the contract if condition is truthy" do
      datetime = ~U[1970-01-01 00:00:00Z]
      timestamp = DateTime.to_unix(datetime)

      code = ~s"""
      @version 1

      condition inherit: [
        content: true
      ]

      condition triggered_by: transaction, as: [
        timestamp: Time.now() == #{timestamp}
      ]

      actions triggered_by: transaction do
        Contract.set_content "hallo"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          timestamp: datetime
        )

      assert {:ok, _} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 nil,
                 datetime
               )
    end

    test "should fail the contract if condition is falsy" do
      datetime = ~U[1970-01-01 00:00:00Z]
      timestamp = DateTime.to_unix(datetime)

      code = ~s"""
      @version 1

      condition inherit: [
        content: true
      ]

      condition triggered_by: transaction, as: [
        timestamp: Time.now() < #{timestamp}
      ]

      actions triggered_by: transaction do
        Contract.set_content "hei"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      trigger_tx =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          timestamp: datetime
        )

      assert {:error, %ConditionRejected{}} =
               Contracts.execute_condition(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 nil,
                 datetime
               )
    end

    test "should run the contract if condition inherit is truthy" do
      datetime = ~U[1970-01-01 00:00:00Z]
      timestamp = DateTime.to_unix(datetime)

      code = ~s"""
      @version 1

      condition inherit: [
        timestamp: Time.now() == #{timestamp},
        content: true
      ]

      actions triggered_by: datetime, at: #{timestamp} do
        Contract.set_content "konnichiwa"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx =
        ContractFactory.create_next_contract_tx(contract_tx,
          content: "konnichiwa",
          timestamp: datetime
        )

      assert {:ok, _} =
               Contracts.execute_condition(
                 :inherit,
                 Contract.from_transaction!(contract_tx),
                 next_tx,
                 nil,
                 datetime
               )
    end

    test "should fail the contract if condition inherit is falsy" do
      datetime = ~U[1970-01-01 00:00:00Z]
      timestamp = DateTime.to_unix(datetime)

      code = ~s"""
      @version 1

      condition inherit: [
        timestamp: Time.now() < #{timestamp}
      ]

      actions triggered_by: datetime, at: #{timestamp} do
        Contract.set_content "ciao"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx =
        ContractFactory.create_next_contract_tx(contract_tx, content: "ciao", timestamp: datetime)

      assert {:error, %ConditionRejected{}} =
               Contracts.execute_condition(
                 :inherit,
                 Contract.from_transaction!(contract_tx),
                 next_tx,
                 nil,
                 datetime
               )
    end
  end
end
