defmodule Archethic.Account.MemTables.UCOLedgerTest do
  use ExUnit.Case

  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  doctest UCOLedger
end
