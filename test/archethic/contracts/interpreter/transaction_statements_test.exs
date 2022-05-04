defmodule Archethic.Contracts.Interpreter.TransactionStatementsTest do
  use ExUnit.Case

  alias Archethic.Contracts.Interpreter.TransactionStatements

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.NFTLedger
  alias Archethic.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  doctest TransactionStatements
end
