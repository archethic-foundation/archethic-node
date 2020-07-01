defmodule UnirisCore.BeaconSlot.NodeInfo do
  defstruct [:public_key, :ready?, :timestamp]

  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          public_key: UnirisCore.Crypto.key(),
          ready?: boolean(),
          timestamp: DateTime.t()
        }

  @doc """
  Serialize into binary format

  ## Examples

        iex> UnirisCore.BeaconSlot.NodeInfo.serialize(%UnirisCore.BeaconSlot.NodeInfo{
        ...>   public_key:  <<0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151, 236,
        ...>    81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94>>,
        ...>   timestamp: ~U[2020-06-25 15:11:53Z],
        ...>   ready?: true
        ...> })
        <<
        # Public key
        0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151, 236,
        81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94,
        # Timestamp
        94, 244, 190, 185,
        # Ready
        1::1
        >>
  """
  def serialize(%__MODULE__{public_key: public_key, timestamp: timestamp, ready?: true}) do
    <<public_key::binary, DateTime.to_unix(timestamp)::32, 1::1>>
  end

  def serialize(%__MODULE__{public_key: public_key, timestamp: timestamp, ready?: _}) do
    <<public_key::binary, timestamp::32, 0::1>>
  end

  @doc """
  Deserialize an encoded NodeInfo

  ## Examples

      iex> %UnirisCore.BeaconSlot.NodeInfo{
      ...>   public_key:  <<0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151, 236,
      ...>    81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94>>,
      ...>   timestamp: ~U[2020-06-25 15:11:53Z],
      ...>   ready?: true
      ...> }
      ...> |> UnirisCore.BeaconSlot.NodeInfo.serialize()
      ...> |> UnirisCore.BeaconSlot.NodeInfo.deserialize()
      {
        %UnirisCore.BeaconSlot.NodeInfo{
          public_key:  <<0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151, 236,
            81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94>>,
          timestamp: ~U[2020-06-25 15:11:53Z],
          ready?: true
        },
        ""
      }
  """
  def deserialize(<<curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), timestamp::32, readyness::1, rest::bitstring>> = rest

    ready? = if readyness == 1, do: true, else: false

    {
      %__MODULE__{
        ready?: ready?,
        public_key: <<curve_id::8>> <> key,
        timestamp: DateTime.from_unix!(timestamp)
      },
      rest
    }
  end
end
