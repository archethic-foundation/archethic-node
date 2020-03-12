defmodule UnirisElection.Impl do
  @moduledoc false

  @callback validation_nodes(transaction :: Transaction.pending()) :: list(Node.t())
  @callback storage_nodes(address :: binary()) :: [Node.t()]
end
