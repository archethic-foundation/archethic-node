defmodule ArchEthic.TransactionChain.TransactionData.Keys do
  @moduledoc """
  Represents section in the transaction data to store secret and authorized keys to
  read the encrypted secret.
  """
  defstruct authorized_keys: %{}, secret: ""

  alias ArchEthic.Crypto

  @type t :: %__MODULE__{
          secret: binary(),
          authorized_keys: %{(public_key :: Crypto.key()) => encrypted_key :: binary()}
        }

  @doc """
  Create a new transaction data keys

  ## Examples

      iex> secret_key = :crypto.strong_rand_bytes(32)
      iex> secret = "important message"
      iex> {pub, _pv} = Crypto.generate_deterministic_keypair("seed")
      iex> %{ authorized_keys: authorized_keys, secret: _} = Keys.new([pub], secret_key, secret)
      iex> Map.keys(authorized_keys)
      [
         <<0, 0, 241, 101, 225, 229, 247, 194, 144, 229, 47, 46, 222, 243, 251, 171, 96,
        203, 174, 116, 191, 211, 39, 79, 142, 94, 225, 222, 51, 69, 201, 84, 161,
        102>>
      ]
  """
  @spec new(list(Crypto.key()), secret_key :: binary(), secret :: binary()) :: t()
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

      iex> %Keys{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
      ...>   }
      ...> }
      ...> |> Keys.serialize()
      <<
        # Secret size
        0, 0, 0, 16,
        # Secret
        205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202,
        # Number of authorized keys
        1,
        # Authorized public key
        0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
        83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9,
        # Encrypted secret key
        139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
        224, 214, 225, 146, 44, 83, 111, 34, 239, 99
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
      ...> 198, 202, 1, 0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22,
      ...> 125, 76, 29, 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54,
      ...> 187, 9, 139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...> 177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...> 233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...> 212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...> 224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
      ...> |> Keys.deserialize()
      {
        %Keys{
          secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
          authorized_keys: %{
            <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
            83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
              <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
                177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
                233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
                212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
                224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
          }
        },
        <<>>
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
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
         <<0::8, origin_id::8, key::binary-32, encrypted_key::binary-size(80), rest::bitstring>>,
         acc
       ) do
    {Map.put(acc, <<0::8, origin_id::8, key::binary>>, encrypted_key), rest}
  end

  defp do_reduce_authorized_keys_bin(
         <<curve_id::8, origin_id::8, public_key::binary-65, encrypted_key::binary-113,
           rest::bitstring>>,
         acc
       )
       when curve_id in [1, 2] do
    {Map.put(acc, <<curve_id::8, origin_id::8, public_key::binary>>, encrypted_key), rest}
  end

  @spec from_map(map()) :: t()
  def from_map(keys = %{}) do
    %__MODULE__{
      secret: Map.get(keys, :secret, ""),
      authorized_keys: Map.get(keys, :authorized_keys, %{})
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{secret: "", authorized_keys: %{}}
  end

  def to_map(keys = %__MODULE__{}) do
    %{
      secret: Map.get(keys, :secret, ""),
      authorized_keys: Map.get(keys, :authorized_keys, %{})
    }
  end

  @doc """
  Determine if the a public key is register inside the authorized public key

  ## Examples

      iex> %Keys{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> }
      ...> |> Keys.authorized_key?(<<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...> 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>)
      true
  """
  @spec authorized_key?(t(), Crypto.key()) :: boolean()
  def authorized_key?(%__MODULE__{authorized_keys: auth_keys}, node_public_key) do
    Map.has_key?(auth_keys, node_public_key)
  end

  @doc """
  List the authorized public keys able to decrypt the cipher

  ## Examples

      iex> %Keys{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> }
      ...> |> Keys.list_authorized_keys()
      [
        <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
          83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>
      ]
  """
  @spec list_authorized_keys(t()) :: list(Crypto.key())
  def list_authorized_keys(%__MODULE__{authorized_keys: auth_keys}), do: Map.keys(auth_keys)

  @doc """
  Get the encrypted key from the authorized public key to decrypt the secret

  ## Examples

      iex> %Keys{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> }
      ...> |> Keys.get_encrypted_key(<<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...> 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>)
      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
  """
  @spec get_encrypted_key(t(), Crypto.key()) :: binary()
  def get_encrypted_key(%__MODULE__{authorized_keys: auth_keys}, public_key) do
    Map.get(auth_keys, public_key)
  end
end
