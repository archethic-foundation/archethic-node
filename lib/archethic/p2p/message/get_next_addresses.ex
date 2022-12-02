defmodule Archethic.P2P.Message.GetNextAddresses do
  @moduledoc """
  Inform a  shard to start repair.
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto

  alias Archethic.Utils

  @type t :: %__MODULE__{address: Crypto.prepended_hash()}

  @doc """
        Serialize GetNextAddresses Struct

        iex> %GetNextAddresses{
        ...> address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        ...> } |> GetNextAddresses.serialize()
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
  """
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @doc """
        Deserialize GetNextAddresses Struct

        iex> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...> 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        ...> |> GetNextAddresses.deserialize()
        {
        %GetNextAddresses{
        address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
         3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        }, ""}

  """
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)

    {%__MODULE__{address: address}, rest}
  end
end
