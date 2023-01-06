defmodule Archethic.P2P.Message.GetBeaconSummariesAggregate do
  @moduledoc """
  Represents a message to get a beacon summary aggregate
  """

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.P2P.Message.NotFound

  @enforce_keys [:date]
  defstruct [:date]

  @type t :: %__MODULE__{
          date: DateTime.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: SummaryAggregate.t() | NotFound.t()
  def process(%__MODULE__{date: date}, _) do
    case BeaconChain.get_summaries_aggregate(date) do
      {:ok, aggregate} ->
        aggregate

      {:error, :not_exists} ->
        %NotFound{}
    end
  end
end
