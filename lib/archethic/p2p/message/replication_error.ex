defmodule Archethic.P2P.Message.ReplicationError do
  @moduledoc """
  Represents a replication error message
  """

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.Mining.Error
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils

  @enforce_keys [:address, :error]
  defstruct [:address, :error]

  @type t :: %__MODULE__{
          address: Crypto.prepended_hash(),
          error: Error.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: address, error: error}, from) do
    Mining.notify_replication_error(address, error, from)
    %Ok{}
  end

  @doc """
  Serialize a replication error message
  """
  @spec serialize(%__MODULE__{}) :: bitstring()
  def serialize(%__MODULE__{address: address, error: error}) do
    <<address::binary, Error.serialize(error)::bitstring>>
  end

  @doc """
  Deserialize a replication error message
  """
  @spec deserialize(bin :: bitstring) :: {%__MODULE__{}, bitstring()}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {error, rest} = Error.deserialize(rest)

    {%__MODULE__{address: address, error: error}, rest}
  end
end
