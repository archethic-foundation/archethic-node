defmodule UnirisCore.BeaconSlot do
  alias __MODULE__.TransactionInfo
  alias __MODULE__.NodeInfo

  defstruct transactions: [], nodes: []

  @type t :: %__MODULE__{
          transactions: list(TransactionInfo.t()),
          nodes: list(NodeInfo.t())
        }

  def add_transaction_info(slot = %__MODULE__{}, info = %TransactionInfo{}) do
    Map.update!(
      slot,
      :transactions,
      &(&1 ++ [info])
    )
  end

  def add_node_info(slot = %__MODULE__{}, info = %NodeInfo{}) do
    Map.update!(
      slot,
      :nodes,
      &(&1 ++ [info])
    )
  end
end
