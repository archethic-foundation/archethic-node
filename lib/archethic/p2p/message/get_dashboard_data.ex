defmodule Archethic.P2P.Message.GetDashboardData do
  @moduledoc """
  Represents a message to request the first public key from a transaction chain
  """

  alias Archethic.Crypto
  alias Archethic.P2P.Message.DashboardData
  alias ArchethicWeb.DashboardMetrics

  defstruct [:since]

  @type t() :: %__MODULE__{
          since: nil | DateTime.t()
        }

  @spec process(t(), Crypto.key()) :: DashboardData.t()
  def process(%__MODULE__{since: nil}, _) do
    %DashboardData{buckets: DashboardMetrics.get_all()}
  end

  def process(%__MODULE__{since: since}, _) do
    %DashboardData{buckets: DashboardMetrics.get_since(since)}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{since: nil}) do
    <<0::1>>
  end

  def serialize(%__MODULE__{since: since}) do
    <<1::1, DateTime.to_unix(since)::32>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<0::1, rest::bitstring>>) do
    {%__MODULE__{}, rest}
  end

  def deserialize(<<1::1, timestamp::32, rest::bitstring>>) do
    {%__MODULE__{since: DateTime.from_unix!(timestamp)}, rest}
  end
end
