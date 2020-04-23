defmodule UnirisCore.Transaction.ValidationStamp.NodeMovements do
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

  @spec new(fee :: float(), rewards :: list(reward())) :: __MODULE__.t()
  def new(fee, rewards) when is_float(fee) and fee >= 0 and is_list(rewards) do
    %__MODULE__{
      fee: fee,
      rewards: rewards
    }
  end
end
