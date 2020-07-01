defmodule UnirisCore.P2P.Message.GetBeaconSlots do
  @enforce_keys [:subsets_slots]
  defstruct [:subsets_slots]

  @type t :: %__MODULE__{
          subsets_slots: %{(subset :: binary()) => datetimes :: list(DateTime.t())}
        }
end
