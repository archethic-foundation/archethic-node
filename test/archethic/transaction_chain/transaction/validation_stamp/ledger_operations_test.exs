defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperationsTest do
  use ArchethicCase

  import ArchethicCase, only: [current_protocol_version: 0]
  use ExUnitProperties

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData

  doctest LedgerOperations
end
