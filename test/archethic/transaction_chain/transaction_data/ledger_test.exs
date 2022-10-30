defmodule Archethic.TransactionChain.TransactionData.LedgerTest do
  @moduledoc false
  use ArchethicCase

  import ArchethicCase, only: [current_transaction_version: 0]

  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  doctest Ledger
end
