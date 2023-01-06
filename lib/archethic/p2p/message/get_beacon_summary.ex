defmodule Archethic.P2P.Message.GetBeaconSummary do
  @moduledoc """
  Represents a message to get a beacon summary
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message.NotFound
  alias Archethic.BeaconChain.Summary

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address}), do: <<26::8, address::binary>>

  @spec process(__MODULE__.t(), Crypto.key()) :: Summary.t() | NotFound.t()
  def process(%__MODULE__{address: address}, _) do
    case BeaconChain.get_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end
end
