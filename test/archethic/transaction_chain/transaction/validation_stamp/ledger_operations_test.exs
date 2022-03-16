defmodule ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperationsTest do
  use ArchEthicCase
  use ExUnitProperties

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionData

  doctest LedgerOperations
end
