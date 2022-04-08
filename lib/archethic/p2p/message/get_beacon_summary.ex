defmodule ArchEthic.P2P.Message.GetBeaconSummary do
  @moduledoc """
  Represents a message to get a beacon summary
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.BeaconChain
  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 26

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  def encode(%__MODULE__{address: address}), do: address

  def decode(message) do
    {address, rest} = Utils.deserialize_address(message)

    {
      %__MODULE__{address: address},
      rest
    }
  end

  def process(%__MODULE__{address: address}) do
    case BeaconChain.get_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end
end
