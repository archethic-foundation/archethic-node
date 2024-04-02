defmodule Archethic.P2P.Message.GetBeaconSummariesAggregate do
  @moduledoc """
  Represents a message to get a beacon summary aggregate
  """

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.NotFound

  @enforce_keys [:date]
  defstruct [:date]

  @type t :: %__MODULE__{
          date: DateTime.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: SummaryAggregate.t() | NotFound.t()
  def process(%__MODULE__{date: date}, _) do
    case BeaconChain.get_summaries_aggregate(date) do
      {:ok, aggregate} ->
        aggregate

      {:error, :not_exists} ->
        %NotFound{}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{date: date}), do: <<DateTime.to_unix(date)::32>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<timestamp::32, rest::bitstring>>) do
    {%__MODULE__{date: DateTime.from_unix!(timestamp)}, rest}
  end
end
