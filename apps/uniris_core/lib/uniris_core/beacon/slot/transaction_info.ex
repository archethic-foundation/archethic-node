defmodule UnirisCore.BeaconSlot.TransactionInfo do
  defstruct [:timestamp, :address, :type, movements_addresses: []]

  alias UnirisCore.Transaction
  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          address: binary(),
          movements_addresses: list(binary()),
          type: Transaction.transaction_type()
        }

  @doc """
  Serialize into binary format

  ## Examples

        iex> UnirisCore.BeaconSlot.TransactionInfo.serialize(%UnirisCore.BeaconSlot.TransactionInfo{
        ...>   address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
        ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
        ...>   timestamp: ~U[2020-06-25 15:11:53Z],
        ...>   type: :transfer,
        ...>   movements_addresses: [
        ...>      <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        ...>        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
        ...>   ]
        ...> })
        <<
        # Address
        0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
        168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247,
        # Timestamp
        94, 244, 190, 185,
        # Type
        2,
        # Nb movements addresses
        0, 1,
        # Movement address
        0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12
        >>
  """
  def serialize(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses
      }) do
    <<address::binary, DateTime.to_unix(timestamp)::32, Transaction.serialize_type(type),
      length(movements_addresses)::16, :erlang.list_to_binary(movements_addresses)::binary>>
  end

  @doc """
  Deserialize an encoded TransactionInfo

  ## Example

      iex> %UnirisCore.BeaconSlot.TransactionInfo{
      ...>   address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z],
      ...>   type: :transfer,
      ...>   movements_addresses: [
      ...>      <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
      ...>   ]
      ...> }
      ...> |> UnirisCore.BeaconSlot.TransactionInfo.serialize()
      ...> |> UnirisCore.BeaconSlot.TransactionInfo.deserialize()
      {
        %UnirisCore.BeaconSlot.TransactionInfo{
          address:  <<0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
              168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
            timestamp: ~U[2020-06-25 15:11:53Z],
            type: :transfer,
            movements_addresses: [
              <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
            ]
        },
        ""
      }
  """
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)

    <<address::binary-size(hash_size), timestamp::32, type::8, nb_movements::16, rest::bitstring>> =
      rest

    {addresses, rest} = deserialize_addresses(rest, nb_movements, [])

    {
      %__MODULE__{
        address: <<hash_id::8, address::binary>>,
        timestamp: DateTime.from_unix!(timestamp),
        type: Transaction.parse_type(type),
        movements_addresses: addresses
      },
      rest
    }
  end

  defp deserialize_addresses(rest, 0, _), do: {[], rest}

  defp deserialize_addresses(rest, nb_addresses, acc) when length(acc) == nb_addresses do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_addresses(<<hash_id::8, rest::bitstring>>, nb_addresses, acc) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), rest::bitstring>> = rest
    deserialize_addresses(rest, nb_addresses, [<<hash_id::8, address::binary>> | acc])
  end
end
