defmodule Archethic.P2P.Message.ShardRepair do
  @moduledoc """
  Inform a  shard to start repair.
  """
  @enforce_keys [:first_address, :storage_address, :io_addresses]
  defstruct [:first_address, :storage_address, :io_addresses]

  alias Archethic.Crypto
  alias Archethic.SelfRepair

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          first_address: Crypto.prepended_hash(),
          storage_address: Crypto.prepended_hash(),
          io_addresses: list(Crypto.prepended_hash())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          first_address: first_address,
          storage_address: storage_address,
          io_addresses: io_addresses
        },
        _
      ) do
    SelfRepair.resync(first_address, storage_address, io_addresses)

    %Ok{}
  end

  @doc """
        Serialize ShardRepair Struct

        iex> %ShardRepair{
        ...> first_address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...> storage_address: <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...>  2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>,
        ...> io_addresses: [
        ...> <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...>  2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>,
        ...> <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...>  2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
        ...> ]
        ...> } |> ShardRepair.serialize()
        # First address
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251,
        # Storage address?
        1::1,
        # Storage address
        0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130,
        # Varint
        1, 2,
        #IO addresses
        0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130,
        0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
  """
  def serialize(%__MODULE__{
        first_address: first_address,
        storage_address: nil,
        io_addresses: io_addresses
      }) do
    <<first_address::binary, 0::1, VarInt.from_value(length(io_addresses))::binary,
      :erlang.list_to_binary(io_addresses)::binary>>
  end

  def serialize(%__MODULE__{
        first_address: first_address,
        storage_address: storage_address,
        io_addresses: io_addresses
      }) do
    <<first_address::binary, 1::1, storage_address::binary,
      VarInt.from_value(length(io_addresses))::binary,
      :erlang.list_to_binary(io_addresses)::binary>>
  end

  @doc """
        DeSerialize ShardRepair Struct

        iex> # First address
        ...> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...> 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251,
        ...> # Storage address?
        ...> 1::1,
        ...> # Storage address
        ...> 0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...> 2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130,
        ...> # Varint
        ...> 1, 2,
        ...> #IO addresses
        ...> 0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...> 2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130,
        ...> 0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
        ...> 2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
        ...> |> ShardRepair.deserialize()
        {
        %ShardRepair{
        first_address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
         3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        storage_address: <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
         2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>,
        io_addresses: [
        <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
         2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>,
        <<0, 0, 106, 248, 193, 217, 112, 140, 200, 141, 33, 81, 243, 92, 207, 242, 72,
         2, 92, 236, 236, 100, 121, 250, 105, 12, 90, 240, 221, 108, 1, 171, 108, 130>>
        ]
        }, ""}

  """
  def deserialize(bin) do
    {first_address, <<storage_address?::1, rest::bitstring>>} = Utils.deserialize_address(bin)

    {storage_address, rest} =
      if storage_address? == 1 do
        Utils.deserialize_address(rest)
      else
        {nil, rest}
      end

    {io_addresses_length, rest} = VarInt.get_value(rest)

    {io_addresses, rest} = Utils.deserialize_addresses(rest, io_addresses_length, [])

    {%__MODULE__{
       first_address: first_address,
       storage_address: storage_address,
       io_addresses: io_addresses
     }, rest}
  end
end
