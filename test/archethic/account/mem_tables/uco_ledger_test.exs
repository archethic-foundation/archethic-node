defmodule ArchEthic.Account.MemTables.UCOLedgerTest do
  use ExUnit.Case

  alias ArchEthic.Account.MemTables.UCOLedger

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

  doctest UCOLedger
end
