defmodule Archethic.P2P.Message.AddressList do
  @moduledoc """
  Inform a  shard to start repair.
  """
  @enforce_keys [:addresses]
  defstruct [:addresses]

  alias Archethic.Crypto

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{addresses: list(Crypto.prepended_hash())}

  @doc """
        Serialize AddressList Struct

        iex> %AddressList{
        ...>   addresses: [
        ...>     {<<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
        ...>        195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...>      ~U[2022-11-27 12:34:56.789Z]},
        ...>     {<<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
        ...>        195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 123, 321>>,
        ...>      ~U[2022-11-27 12:34:54.321Z]}
        ...>   ]
        ...> }
        ...> |> AddressList.serialize()
        # VarInt
        <<
          1,
          2,
          # Addresses
          0,
          0,
          94,
          5,
          249,
          103,
          126,
          31,
          43,
          57,
          25,
          14,
          187,
          133,
          59,
          234,
          201,
          172,
          3,
          195,
          43,
          81,
          81,
          146,
          164,
          202,
          147,
          218,
          207,
          204,
          31,
          185,
          73,
          251,
          0,
          0,
          1,
          132,
          185,
          21,
          96,
          149,
          0,
          0,
          94,
          5,
          249,
          103,
          126,
          31,
          43,
          57,
          25,
          14,
          187,
          133,
          59,
          234,
          201,
          172,
          3,
          195,
          43,
          81,
          81,
          146,
          164,
          202,
          147,
          218,
          207,
          204,
          31,
          185,
          123,
          321,
          0,
          0,
          1,
          132,
          185,
          21,
          86,
          241
        >>
  """
  def serialize(%__MODULE__{addresses: addresses}) do
    addresses_bin =
      addresses
      |> Stream.map(fn {address, timestamp} ->
        <<address::binary, DateTime.to_unix(timestamp, :millisecond)::64>>
      end)
      |> Enum.to_list()
      |> :erlang.list_to_binary()

    <<VarInt.from_value(length(addresses))::binary, addresses_bin::binary>>
  end

  @doc """
        Deserialize AddressList Struct

        iex> # VarInt
        ...> <<
        ...>   1,
        ...>   2,
        ...>   # Addresses
        ...>   0,
        ...>   0,
        ...>   94,
        ...>   5,
        ...>   249,
        ...>   103,
        ...>   126,
        ...>   31,
        ...>   43,
        ...>   57,
        ...>   25,
        ...>   14,
        ...>   187,
        ...>   133,
        ...>   59,
        ...>   234,
        ...>   201,
        ...>   172,
        ...>   3,
        ...>   195,
        ...>   43,
        ...>   81,
        ...>   81,
        ...>   146,
        ...>   164,
        ...>   202,
        ...>   147,
        ...>   218,
        ...>   207,
        ...>   204,
        ...>   31,
        ...>   185,
        ...>   73,
        ...>   251,
        ...>   0,
        ...>   0,
        ...>   1,
        ...>   132,
        ...>   185,
        ...>   21,
        ...>   96,
        ...>   149,
        ...>   0,
        ...>   0,
        ...>   94,
        ...>   5,
        ...>   249,
        ...>   103,
        ...>   126,
        ...>   31,
        ...>   43,
        ...>   57,
        ...>   25,
        ...>   14,
        ...>   187,
        ...>   133,
        ...>   59,
        ...>   234,
        ...>   201,
        ...>   172,
        ...>   3,
        ...>   195,
        ...>   43,
        ...>   81,
        ...>   81,
        ...>   146,
        ...>   164,
        ...>   202,
        ...>   147,
        ...>   218,
        ...>   207,
        ...>   204,
        ...>   31,
        ...>   185,
        ...>   123,
        ...>   321,
        ...>   0,
        ...>   0,
        ...>   1,
        ...>   132,
        ...>   185,
        ...>   21,
        ...>   86,
        ...>   241
        ...> >>
        ...> |> AddressList.deserialize()
        {
          %AddressList{
            addresses: [
              {<<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
                 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
               ~U[2022-11-27 12:34:56.789Z]},
              {<<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
                 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 123, 321>>,
               ~U[2022-11-27 12:34:54.321Z]}
            ]
          },
          ""
        }

  """
  def deserialize(bin) do
    {addresses_length, rest} = VarInt.get_value(bin)

    {addresses, rest} = deserialize_list(rest, addresses_length, [])

    {%__MODULE__{addresses: addresses}, rest}
  end

  defp deserialize_list(rest, 0, _), do: {[], rest}

  defp deserialize_list(rest, nb_elt, acc) when length(acc) == nb_elt do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_list(rest, nb_elt, acc) do
    {elt, rest} = deserialize_elt(rest)
    deserialize_list(rest, nb_elt, [elt | acc])
  end

  defp deserialize_elt(bin) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(bin)

    {{address, DateTime.from_unix!(timestamp, :millisecond)}, rest}
  end
end
