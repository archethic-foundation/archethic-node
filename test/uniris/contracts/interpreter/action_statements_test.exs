defmodule Uniris.Contracts.Interpreter.ActionStatementsTest do
  use ExUnit.Case

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Interpreter.ActionStatements

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.NFTLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  doctest ActionStatements
end
