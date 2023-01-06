defmodule Archethic.P2P.Message.BeaconSummaryList do
  @moduledoc """
  Represents a message with a list of beacon summaries
  """

  alias Archethic.BeaconChain.Summary
  alias Archethic.Utils.VarInt

  defstruct summaries: []

  @type t :: %__MODULE__{
          summaries: list(Summary.t())
        }

  def encode(%__MODULE__{summaries: summaries}) do
    summaries_bin =
      Stream.map(summaries, &Summary.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_summaries_length = Enum.count(summaries) |> VarInt.from_value()

    <<237::8, encoded_summaries_length::binary, summaries_bin::bitstring>>
  end
end
