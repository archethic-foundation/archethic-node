defmodule Archethic.P2P.Message.FirstTransactionAddress do
  @moduledoc false
  alias Archethic.Utils
  @enforce_keys [:address]
  defstruct [:address]

  @type t() :: %__MODULE__{
          address: binary()
        }

  @doc """
         Serialize FirstTransactionAddress Struct

        iex> %FirstTransactionAddress{
        ...> address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        ...> } |> FirstTransactionAddress.serialize()
        #address
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
  """
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @doc """
        DeSerialize FirstTransactionAddress Struct

        iex> # First address
        ...> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...> 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        ...> |> FirstTransactionAddress.deserialize()
        {
        %FirstTransactionAddress{
        address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
         3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        }, ""}

  """
  def deserialize(bin) do
    {address, <<rest::bitstring>>} = Utils.deserialize_address(bin)

    {%__MODULE__{address: address}, rest}
  end
end
