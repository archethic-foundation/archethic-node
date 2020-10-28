defmodule Uniris.Account.MemTables.UCOLedgerTest do
  use ExUnit.Case

  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionInput

  doctest UCOLedger
end
