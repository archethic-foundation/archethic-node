defmodule UnirisCore.TransactionData.Keys do
  @moduledoc """
  Represents section in the transaction data to store secret and authorized keys to
  read the encrypted secret.
  """
  defstruct authorized_keys: %{}, secret: ""

  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          secret: binary(),
          authorized_keys: %{(public_key :: Crypto.key()) => encrypted_key :: binary()}
        }

  @doc """
  Create a new transaction data keys

  ## Examples

      iex> secret_key = :crypto.strong_rand_bytes(32)
      iex> secret = "important message"
      iex> {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair("seed")
      iex> %{ authorized_keys: authorized_keys, secret: _} = UnirisCore.TransactionData.Keys.new([pub], secret_key, secret)
      iex> Map.keys(authorized_keys)
      [ <<0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8, 130, 22, 212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>> ]
  """
  @spec new(list(Crypto.key()), secret_key :: binary(), secret :: binary()) :: __MODULE__.t()
  def new(authorized_public_keys, secret_key, secret)
      when is_list(authorized_public_keys) and is_binary(secret_key) do
    Enum.reduce(authorized_public_keys, %__MODULE__{secret: secret}, fn public_key, acc = %{} ->
      encrypted_secret_key = Crypto.ec_encrypt(secret_key, public_key)
      Map.update!(acc, :authorized_keys, &Map.put(&1, public_key, encrypted_secret_key))
    end)
  end

  @doc """
  Serialize the transaction data keys

  ## Examples

      iex> UnirisCore.TransactionData.Keys.serialize(%UnirisCore.TransactionData.Keys{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>      <<0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> })
      <<
        # Secret size
        0, 0, 0, 16,
        # Secret
        205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202,
        # Number of authorized keys
        1,
        # Authorized public key
        0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
        83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9,
        # Encrypted secret key
        139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246
      >>
  """
  def serialize(%__MODULE__{secret: secret, authorized_keys: authorized_keys}) do
    authorized_keys_bin =
      Enum.reduce(authorized_keys, <<>>, fn {public_key, encrypted_key}, acc ->
        <<public_key::binary, encrypted_key::binary>> <> acc
      end)

    nb_authorized_keys = authorized_keys |> Map.keys() |> length
    <<byte_size(secret)::32, secret::binary, nb_authorized_keys::8, authorized_keys_bin::binary>>
  end

  @doc """
  Deserialize a transaction data keys encoded

  ## Examples

      iex> <<0, 0, 0, 16, 205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206,
      ...> 198, 202, 1, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22,
      ...> 125, 76, 29, 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54,
      ...> 187, 9, 139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...> 177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...> 233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...> 212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...> 224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...> |> UnirisCore.TransactionData.Keys.deserialize()
      {
        %UnirisCore.TransactionData.Keys{
          secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
          authorized_keys: %{
            <<0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
            83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
              <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
                177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
                233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
                212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
                224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
          }
        },
        <<>>
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
  def deserialize(<<secret_size::32, secret::binary-size(secret_size), 0::8, rest::bitstring>>) do
    {
      %__MODULE__{
        secret: secret
      },
      rest
    }
  end

  def deserialize(
        <<secret_size::32, secret::binary-size(secret_size), nb_authorized_keys::8,
          rest::bitstring>>
      ) do
    {authorized_keys, rest} = reduce_authorized_keys_bin(rest, nb_authorized_keys, %{})

    {%__MODULE__{
       secret: secret,
       authorized_keys: authorized_keys
     }, rest}
  end

  defp reduce_authorized_keys_bin(rest, nb_authorized_keys, acc) do
    if length(Map.keys(acc)) == nb_authorized_keys do
      {acc, rest}
    else
      {acc, rest} = do_reduce_authorized_keys_bin(rest, acc)
      reduce_authorized_keys_bin(rest, nb_authorized_keys, acc)
    end
  end

  defp do_reduce_authorized_keys_bin(
         <<0::8, key::binary-32, encrypted_key::binary-84, rest::bitstring>>,
         acc
       ) do
    {Map.put(acc, <<0::8, key::binary>>, encrypted_key), rest}
  end

  defp do_reduce_authorized_keys_bin(
         <<curve_id::8, public_key::binary-65, encrypted_key::binary-113, rest::bitstring>>,
         acc
       )
       when curve_id in [1, 2] do
    {Map.put(acc, <<curve_id::8, public_key::binary>>, encrypted_key), rest}
  end
end
