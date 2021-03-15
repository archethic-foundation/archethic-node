defmodule Uniris.Contracts.Interpreter.TransactionStatementsTest do
  use ExUnit.Case

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Interpreter.TransactionStatements

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.NFTLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  doctest TransactionStatements
end
