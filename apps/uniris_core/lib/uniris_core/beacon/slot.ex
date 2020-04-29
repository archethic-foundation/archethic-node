defmodule UnirisCore.BeaconSlot do
  alias __MODULE__.TransactionInfo
  alias __MODULE__.NodeInfo

  defstruct transactions: [], nodes: []

  @type t :: %__MODULE__{
          transactions: list(TransactionInfo.t()),
          nodes: list(NodeInfo.t())
        }

  def add_transaction_info(
        slot = %__MODULE__{transactions: transactions},
        info = %TransactionInfo{address: tx_address}
      ) do
    if Enum.any?(transactions, &(&1.address == tx_address)) do
      slot
    else
      Map.update!(
        slot,
        :transactions,
        &(&1 ++ [info])
      )
    end
  end

  def add_node_info(slot = %__MODULE__{}, info = %NodeInfo{}) do
    Map.update!(
      slot,
      :nodes,
      &(&1 ++ [info])
    )
  end
end
