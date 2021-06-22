defmodule ArchEthic.Contracts.Interpreter.TransactionStatementsTest do
  use ExUnit.Case

  alias ArchEthic.Contracts.Contract
  alias ArchEthic.Contracts.Interpreter.TransactionStatements

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

  doctest TransactionStatements
end
