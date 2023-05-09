defmodule Archethic.Contracts.Interpreter.Library.Common.TimeTest do
  @moduledoc """
  We test via the Interpreter.execute because it's where we define the time to use
  """

  use ArchethicCase

  alias Archethic.TransactionFactory
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Library.Common.Time

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Time

  describe "now/0" do
    test "should work in the action block" do
      datetime = DateTime.utc_now() |> DateTime.truncate(:second)
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
        Interpreter.execute(
          {:datetime, datetime},
          Contract.from_transaction!(contract_tx),
          nil,
          []
        )

      assert %Transaction{data: %TransactionData{content: content}} = tx
      assert String.to_integer(content) == timestamp
    end

    test "should run the contract if condition is truthy" do
      datetime = DateTime.utc_now() |> DateTime.truncate(:second)
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

      assert {:ok, tx} =
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 [trigger_tx]
               )

      assert %Transaction{data: %TransactionData{content: "hallo"}} = tx
    end

    test "should fail the contract if condition is falsy" do
      datetime = DateTime.utc_now() |> DateTime.truncate(:second)
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

      assert {:error, :invalid_transaction_constraints} =
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 trigger_tx,
                 [trigger_tx]
               )
    end

    test "should run the contract if condition inherit is truthy" do
      datetime = DateTime.utc_now() |> DateTime.truncate(:second)
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

      assert {:ok, %Transaction{}} =
               Interpreter.execute(
                 {:datetime, datetime},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 []
               )
    end

    test "should fail the contract if condition inherit is falsy" do
      datetime = DateTime.utc_now() |> DateTime.truncate(:second)
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

      assert {:error, :invalid_inherit_constraints} =
               Interpreter.execute(
                 {:datetime, datetime},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 []
               )
    end
  end
end
