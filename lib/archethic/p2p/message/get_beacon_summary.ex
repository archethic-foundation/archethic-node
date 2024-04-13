defmodule Archethic.P2P.Message.GetBeaconSummary do
  @moduledoc """
  Represents a message to get a beacon summary
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.NotFound
  alias Archethic.BeaconChain.Summary

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Summary.t() | NotFound.t()
  def process(%__MODULE__{address: address}, _) do
    case BeaconChain.get_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}), do: <<address::binary>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::binary>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{address: address},
      rest
    }
  end
end
