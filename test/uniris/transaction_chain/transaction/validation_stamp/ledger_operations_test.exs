defmodule Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperationsTest do
  use UnirisCase
  use ExUnitProperties

  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  doctest LedgerOperations
end
