defmodule Uniris.TransactionChain.MemTables.ChainLookupTest do
  use ExUnit.Case

  import Mox

  setup :set_mox_global

  alias Uniris.Crypto

  alias Uniris.TransactionChain.MemTables.ChainLookup

  doctest ChainLookup
end
