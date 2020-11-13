defmodule Uniris.Account.MemTables.NFTLedgerTest do
  use ExUnit.Case

  alias Uniris.Account.MemTables.NFTLedger

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionInput

  doctest NFTLedger
end
