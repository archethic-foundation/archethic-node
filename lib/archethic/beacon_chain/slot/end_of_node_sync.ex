defmodule Archethic.BeaconChain.Slot.EndOfNodeSync do
  @moduledoc """
  Represents an information stored in the Beacon chain to notify when a node finished its synchronization
  """
  defstruct [:public_key, :timestamp]

  alias Archethic.Crypto
  alias Archethic.Utils

  @type t :: %__MODULE__{
          public_key: Crypto.key(),
          timestamp: DateTime.t()
        }

  @doc """
  Serialize into binary format

  ## Examples

        iex> %EndOfNodeSync{
        ...>   public_key:
        ...>     <<0, 0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151,
        ...>       236, 81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94>>,
        ...>   timestamp: ~U[2020-06-25 15:11:53Z]
        ...> }
        ...> |> EndOfNodeSync.serialize()
        <<
          # Public key
          0,
          0,
          27,
          7,
          231,
          56,
          158,
          71,
          37,
          55,
          178,
          16,
          94,
          82,
          36,
          5,
          33,
          248,
          1,
          151,
          236,
          81,
          191,
          35,
          110,
          247,
          4,
          87,
          172,
          199,
          154,
          209,
          17,
          94,
          # Timestamp
          94,
          244,
          190,
          185
        >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{public_key: public_key, timestamp: timestamp}) do
    <<public_key::binary, DateTime.to_unix(timestamp)::32>>
  end

  @doc """
  Deserialize an encoded EndOfNodeSync

  ## Examples

      iex> <<0, 0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151, 236,
      ...>   81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94, 94, 244, 190, 185>>
      ...> |> EndOfNodeSync.deserialize()
      {
        %EndOfNodeSync{
          public_key:
            <<0, 0, 27, 7, 231, 56, 158, 71, 37, 55, 178, 16, 94, 82, 36, 5, 33, 248, 1, 151, 236,
              81, 191, 35, 110, 247, 4, 87, 172, 199, 154, 209, 17, 94>>,
          timestamp: ~U[2020-06-25 15:11:53Z]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(data) when is_bitstring(data) do
    {public_key, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_public_key(data)

    {
      %__MODULE__{
        public_key: public_key,
        timestamp: DateTime.from_unix!(timestamp)
      },
      rest
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{public_key: public_key, timestamp: timestamp}) do
    %{
      public_key: public_key,
      timestamp: timestamp
    }
  end

  @spec cast(map()) :: t()
  def cast(%{public_key: public_key, timestamp: timestamp}) do
    %__MODULE__{
      public_key: public_key,
      timestamp: timestamp
    }
  end
end
