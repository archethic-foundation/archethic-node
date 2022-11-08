defmodule Archethic.P2P.Message.ShardRepair do
  @moduledoc """
  Inform a  shard to start repair.
  """
  @enforce_keys [:last_address, :genesis_address]
  defstruct [:last_address, :genesis_address]

  alias Archethic.Utils

  @type t :: %__MODULE__{
          genesis_address: binary(),
          last_address: binary()
        }

  @doc """
        Serialize ShardRepair Struct

        iex> %ShardRepair{
        ...> genesis_address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...> last_address: <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...>  2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
        ...> } |> ShardRepair.serialize()
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251,
        0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
         2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
  """
  def serialize(%__MODULE__{
        genesis_address: genesis_address,
        last_address: last_address
      }) do
    <<genesis_address::binary, last_address::binary>>
  end

  @doc """
        DeSerialize ShardRepair Struct

        iex> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...> 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251,
        ...> 0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...> 2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
        ...> |> ShardRepair.deserialize()
        {
          %ShardRepair{
        genesis_address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
         last_address: <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
          2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
        }, ""}

  """
  def deserialize(bin) do
    {genesis_address, rest} = Utils.deserialize_address(bin)
    {last_address, rest} = Utils.deserialize_address(rest)

    {%__MODULE__{
       genesis_address: genesis_address,
       last_address: last_address
     }, rest}
  end

  def cast(%__MODULE__{
        genesis_address: genesis_address,
        last_address: last_address
      }) do
    %{genesis_address: genesis_address, last_address: last_address}
  end
end
