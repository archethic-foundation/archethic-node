defmodule ArchEthic.P2P.Message.BeaconSummaryList do
  @moduledoc """
  Represents a message with a list of beacon summaries
  """

  alias ArchEthic.BeaconChain.Summary

  defstruct summaries: []

  @type t :: %__MODULE__{
          summaries: list(Summary.t())
        }

  use ArchEthic.P2P.Message, message_id: 237

  def encode(%__MODULE__{summaries: summaries}) do
    summaries_bin =
      Stream.map(summaries, &Summary.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<Enum.count(summaries)::32, summaries_bin::binary>>
  end

  def decode(<<nb_summaries::32, rest::bitstring>>) do
    {summaries, rest} = deserialize_summaries(rest, nb_summaries, [])

    {
      %__MODULE__{summaries: summaries},
      rest
    }
  end

  defp deserialize_summaries(rest, 0, _), do: {[], rest}

  defp deserialize_summaries(rest, nb_summaries, acc) when nb_summaries == length(acc),
    do: {Enum.reverse(acc), rest}

  defp deserialize_summaries(rest, nb_summaries, acc) do
    {summary, rest} = Summary.deserialize(rest)
    deserialize_summaries(rest, nb_summaries, [summary | acc])
  end

  def process(%__MODULE__{}) do
  end
end
