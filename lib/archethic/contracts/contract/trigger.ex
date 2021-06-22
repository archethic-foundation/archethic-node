defmodule ArchEthic.Contracts.Contract.Trigger do
  @moduledoc """
  Represents the smart contract triggers
  """

  defstruct [:type, :actions, opts: []]

  @type timestamp :: non_neg_integer()
  @type interval :: binary()
  @type address :: binary()

  @type type() :: :datetime | :interval | :transaction | :oracle

  @type t :: %__MODULE__{
          type: type(),
          opts: Keyword.t(),
          actions: Macro.t()
        }
end
