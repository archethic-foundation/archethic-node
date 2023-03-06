defmodule Archethic.P2P.Message.GetNetworkStats do
  @moduledoc """
  Represents a message to get the network stats from the beacon summary cache
  """

  @enforce_keys :subset
  defstruct [:subset]

  alias Archethic.BeaconChain
  alias Archethic.Crypto
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.NetworkStats

  @type t :: %__MODULE__{
          subset: binary()
        }

  @doc """
  Serialize the get network stats message into binary

  ## Examples
      
      iex> %GetNetworkStats{subset: <<0>>} |> GetNetworkStats.serialize()
      <<0>>
  """
  def serialize(%__MODULE__{subset: subset}) do
    <<subset::binary>>
  end

  @doc """
  Deserialize the binary into the get network stats message

  ## Examples
      
      iex> <<0>> |> GetNetworkStats.deserialize()
      {
        %GetNetworkStats{subset: <<0>>},
        ""
      }
  """
  def deserialize(<<subset::binary-size(1), rest::bitstring>>) do
    {
      %__MODULE__{subset: subset},
      rest
    }
  end

  @doc """
  Process the message to get the network stats from the summary cache
  """
  @spec process(t(), Crypto.key()) :: Message.response()
  def process(%__MODULE__{subset: subset}, _node_public_key) do
    stats = BeaconChain.get_network_stats(subset)
    %NetworkStats{stats: stats}
  end
end
