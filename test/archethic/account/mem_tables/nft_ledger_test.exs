defmodule ArchEthic.Account.MemTables.NFTLedgerTest do
  use ExUnit.Case

  alias ArchEthic.Account.MemTables.NFTLedger

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

  doctest NFTLedger
end
