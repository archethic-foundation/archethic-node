defmodule Archethic.Account.MemTables.TokenLedgerTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.Account.MemTables.TokenLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  doctest TokenLedger
end
