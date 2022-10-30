defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovementTest do
  use ArchethicCase

  import ArchethicCase, only: [current_protocol_version: 0]

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  doctest TransactionMovement
end
