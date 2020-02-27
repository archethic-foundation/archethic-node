defmodule UnirisChain.Transaction.ValidationStamp.NodeMovements do
  @moduledoc """
  Represents transaction node movements including the transaction fee and the amount rewarded to
  involved nodes (welcome node, coordinator node, cross validation nodes, previous storage nodes)
  """
  @enforce_keys [:fee, :rewards]
  defstruct [:fee, :rewards]

  @type reward :: {public_key :: binary(), amount :: float()}

  @type t :: %__MODULE__{
          fee: float(),
          rewards: list(reward())
        }
end
