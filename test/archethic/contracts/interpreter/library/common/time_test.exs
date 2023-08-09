defmodule Archethic.Contracts.Interpreter.Library.Common.TimeTest do
  use ArchethicCase

  alias Archethic.TransactionFactory
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter.Library.Common.Time

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

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

      contract_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code
        )

      {:ok, tx} =
        Contracts.execute_trigger(
          {:datetime, datetime},
          Contract.from_transaction!(contract_tx),
          nil,
          nil,
          time_now: datetime
        )

      assert %Transaction{data: %TransactionData{content: content}} = tx
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

      condition transaction: [
        timestamp: Time.now() == #{timestamp}
      ]

      actions triggered_by: transaction do
        Contract.set_content "hallo"
      end
      """

      contract_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code
        )

      trigger_tx =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          timestamp: datetime
        )

      assert Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               trigger_tx,
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

      condition transaction: [
        timestamp: Time.now() < #{timestamp}
      ]

      actions triggered_by: transaction do
        Contract.set_content "hei"
      end
      """

      contract_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code
        )

      trigger_tx =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          timestamp: datetime
        )

      refute Contracts.valid_condition?(
               :transaction,
               Contract.from_transaction!(contract_tx),
               trigger_tx,
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

      contract_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code
        )

      next_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code,
          content: "konnichiwa",
          timestamp: datetime
        )

      assert Contracts.valid_condition?(
               :inherit,
               Contract.from_transaction!(contract_tx),
               next_tx,
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

      contract_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code
        )

      next_tx =
        TransactionFactory.create_valid_transaction([],
          type: :contract,
          code: code,
          content: "ciao",
          timestamp: datetime
        )

      refute Contracts.valid_condition?(
               :inherit,
               Contract.from_transaction!(contract_tx),
               next_tx,
               datetime
             )
    end
  end
end
