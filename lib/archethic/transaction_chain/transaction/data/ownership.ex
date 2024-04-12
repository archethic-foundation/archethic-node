defmodule Archethic.TransactionChain.TransactionData.Ownership do
  @moduledoc """
  Represents an ownership of a secret and the authorized public keys able to
  read the encrypted secret
  """
  defstruct authorized_keys: %{}, secret: ""

  alias Archethic.Crypto
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          secret: binary(),
          authorized_keys: %{(public_key :: Crypto.key()) => encrypted_key :: binary()}
        }

  @doc """
  Create a new ownership by passing its secret with its authorized keys

  ## Examples

      iex> secret_key = :crypto.strong_rand_bytes(32)
      ...> secret = "important message"
      ...> {pub, _pv} = Crypto.generate_deterministic_keypair("seed")
      ...> %Ownership{authorized_keys: authorized_keys} = Ownership.new(secret, secret_key, [pub])
      ...> Map.keys(authorized_keys)
      [
        <<0, 1, 241, 101, 225, 229, 247, 194, 144, 229, 47, 46, 222, 243, 251, 171, 96, 203, 174,
          116, 191, 211, 39, 79, 142, 94, 225, 222, 51, 69, 201, 84, 161, 102>>
      ]
  """
  @spec new(
          secret :: binary(),
          secret_key :: binary(),
          authorized_keys :: list(Crypto.key())
        ) :: t()
  def new(secret, secret_key, authorized_keys)
      when is_binary(secret) and is_binary(secret_key) and is_list(authorized_keys) do
    %__MODULE__{
      secret: secret,
      authorized_keys:
        Enum.map(authorized_keys, fn public_key ->
          {public_key, Crypto.ec_encrypt(secret_key, public_key)}
        end)
        |> Enum.into(%{})
    }
  end

  @doc """
  Serialize an ownership

  ## Examples

      iex> %Ownership{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>     <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83,
      ...>       14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187,
      ...>       9>> =>
      ...>       <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>         177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>         233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>         212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>         224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
      ...>   }
      ...> }
      ...> |> Ownership.serialize(current_transaction_version())
      <<0, 0, 0, 16, 205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202, 1, 1,
        0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83, 14, 154,
        60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9, 139, 100, 20, 32, 187, 77, 56, 30,
        116, 207, 34, 95, 157, 128, 208, 115, 113, 177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181,
        113, 247, 75, 151, 127, 41, 7, 233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105,
        225, 218, 91, 92, 212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188,
        244, 7, 224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
  """
  @spec serialize(ownership :: t(), tx_version :: pos_integer()) :: bitstring()
  def serialize(%__MODULE__{secret: secret, authorized_keys: authorized_keys}, _tx_version) do
    authorized_keys_bin =
      Enum.map(authorized_keys, fn {public_key, encrypted_key} ->
        <<public_key::binary, encrypted_key::binary>>
      end)
      |> :erlang.list_to_binary()

    serialized_length = VarInt.from_value(map_size(authorized_keys))

    <<byte_size(secret)::32, secret::binary, serialized_length::binary,
      authorized_keys_bin::binary>>
  end

  @doc """
  Deserialize an encoded ownership

  ## Examples

      iex> <<0, 0, 0, 16, 205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202, 1,
      ...>   1, 0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83,
      ...>   14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9, 139, 100, 20, 32,
      ...>   187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113, 177, 45, 9, 93, 107, 90,
      ...>   254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7, 233, 227, 98, 209, 211, 97, 117,
      ...>   68, 101, 59, 121, 214, 105, 225, 218, 91, 92, 212, 162, 48, 18, 15, 181, 70, 103, 32,
      ...>   141, 4, 64, 107, 93, 117, 188, 244, 7, 224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
      ...> |> Ownership.deserialize(1)
      {
        %Ownership{
          secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
          authorized_keys: %{
            <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83, 14,
              154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187,
              9>> =>
              <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113, 177,
                45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7, 233, 227,
                98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92, 212, 162, 48,
                18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7, 224, 214, 225, 146,
                44, 83, 111, 34, 239, 99>>
          }
        },
        <<>>
      }
  """
  @spec deserialize(data :: bitstring(), tx_version :: pos_integer()) :: {t(), bitstring}
  def deserialize(
        <<secret_size::32, secret::binary-size(secret_size), rest::bitstring>>,
        _tx_version
      ) do
    {nb_authorized_keys_len, rest} = rest |> VarInt.get_value()
    {authorized_keys, rest} = reduce_authorized_keys_bin(rest, nb_authorized_keys_len, %{})

    {%__MODULE__{
       secret: secret,
       authorized_keys: authorized_keys
     }, rest}
  end

  defp reduce_authorized_keys_bin(rest, 0, _), do: {%{}, rest}

  defp reduce_authorized_keys_bin(rest, nb_authorized_keys, acc)
       when map_size(acc) == nb_authorized_keys,
       do: {acc, rest}

  defp reduce_authorized_keys_bin(
         <<0::8, origin_id::8, key::binary-32, encrypted_key::binary-size(80), rest::bitstring>>,
         nb_authorized_keys,
         acc
       ) do
    reduce_authorized_keys_bin(
      rest,
      nb_authorized_keys,
      Map.put(acc, <<0::8, origin_id::8, key::binary>>, encrypted_key)
    )
  end

  defp reduce_authorized_keys_bin(
         <<curve_id::8, origin_id::8, public_key::binary-65, encrypted_key::binary-113,
           rest::bitstring>>,
         nb_authorized_keys,
         acc
       )
       when curve_id in [1, 2] do
    reduce_authorized_keys_bin(
      rest,
      nb_authorized_keys,
      Map.put(acc, <<curve_id::8, origin_id::8, public_key::binary>>, encrypted_key)
    )
  end

  @spec cast(map()) :: t()
  def cast(ownership = %{}) do
    %__MODULE__{
      secret: Map.get(ownership, :secret, <<>>),
      authorized_keys: Map.get(ownership, :authorized_keys, %{})
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{secret: <<>>, authorized_keys: []}
  end

  def to_map(%__MODULE__{secret: secret, authorized_keys: authorized_keys}) do
    %{
      secret: secret,
      authorized_keys: authorized_keys
    }
  end

  @doc """
  Determine if the a public key is register inside the authorized public key

  ## Examples

      iex> %Ownership{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>     <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83,
      ...>       14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187,
      ...>       9>> =>
      ...>       <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>         177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>         233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>         212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>         224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> }
      ...> |> Ownership.authorized_public_key?(
      ...>   <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83, 14,
      ...>     154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>
      ...> )
      true
  """
  @spec authorized_public_key?(t(), Crypto.key()) :: boolean()
  def authorized_public_key?(%__MODULE__{authorized_keys: auth_keys}, node_public_key)
      when is_binary(node_public_key) do
    Map.has_key?(auth_keys, node_public_key)
  end

  @doc """
  List all the authorized keys

  ## Examples

      iex> %Ownership{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>     <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83,
      ...>       14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187,
      ...>       9>> =>
      ...>       <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>         177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>         233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>         212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>         224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> }
      ...> |> Ownership.list_authorized_public_keys()
      [
        <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83, 14, 154,
          60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>
      ]
  """
  @spec list_authorized_public_keys(t()) :: list(Crypto.key())
  def list_authorized_public_keys(%__MODULE__{authorized_keys: auth_keys}) do
    Map.keys(auth_keys)
  end

  @doc """
  Get the encrypted key from the authorized public key to decrypt the secret

  ## Examples

      iex> %Ownership{
      ...>   secret: <<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>,
      ...>   authorized_keys: %{
      ...>     <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83,
      ...>       14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187,
      ...>       9>> =>
      ...>       <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>         177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>         233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>         212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>         224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }
      ...> }
      ...> |> Ownership.get_encrypted_key(
      ...>   <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29, 83, 14,
      ...>     154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>
      ...> )
      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113, 177, 45, 9,
        93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7, 233, 227, 98, 209, 211,
        97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92, 212, 162, 48, 18, 15, 181, 70, 103,
        32, 141, 4, 64, 107, 93, 117, 188, 244, 7, 224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1,
        126, 241, 246>>
  """
  @spec get_encrypted_key(
          t(),
          authorized_public_key :: Crypto.key()
        ) :: binary()
  def get_encrypted_key(%__MODULE__{authorized_keys: auth_keys}, public_key)
      when is_binary(public_key) do
    Map.get(auth_keys, public_key)
  end

  @doc """
  Verify if the data format in the ownerships is valid (public key and encrypted key)

  ## Examples

      iex> secret = random_secret()
      ...> {pub, _} = Crypto.derive_keypair(:crypto.strong_rand_bytes(32), 0, :ed25519)
      ...> authorized_keys = %{pub => random_encrypted_key(pub)}
      ...> 
      ...> %Ownership{secret: secret, authorized_keys: authorized_keys}
      ...> |> Ownership.validate_format()
      :ok

      iex> secret = random_secret()
      ...> {pub, _} = Crypto.derive_keypair(:crypto.strong_rand_bytes(32), 0, :secp256k1)
      ...> authorized_keys = %{pub => random_encrypted_key(pub)}
      ...> 
      ...> %Ownership{secret: secret, authorized_keys: authorized_keys}
      ...> |> Ownership.validate_format()
      :ok

      iex> secret = ""
      ...> {pub, _} = Crypto.derive_keypair(:crypto.strong_rand_bytes(32), 0, :ed25519)
      ...> authorized_keys = %{pub => :crypto.strong_rand_bytes(80)}
      ...> 
      ...> %Ownership{secret: secret, authorized_keys: authorized_keys}
      ...> |> Ownership.validate_format()
      {:error, :empty_secret}

      iex> secret = random_secret()
      ...> authorized_keys = %{}
      ...> 
      ...> %Ownership{secret: secret, authorized_keys: authorized_keys}
      ...> |> Ownership.validate_format()
      {:error, :empty_authorized_keys}

      iex> secret = random_secret()
      ...> {pub, _} = Crypto.derive_keypair(:crypto.strong_rand_bytes(32), 0, :ed25519)
      ...> authorized_keys = %{pub => :crypto.strong_rand_bytes(55)}
      ...> 
      ...> %Ownership{secret: secret, authorized_keys: authorized_keys}
      ...> |> Ownership.validate_format()
      {:error, :invalid_encrypted_key}

      iex> secret = random_secret()
      ...> authorized_keys = %{:crypto.strong_rand_bytes(20) => :crypto.strong_rand_bytes(80)}
      ...> 
      ...> %Ownership{secret: secret, authorized_keys: authorized_keys}
      ...> |> Ownership.validate_format()
      {:error, :invalid_public_key}
  """
  @spec validate_format(ownership :: t()) ::
          :ok
          | {:error,
             :empty_secret | :empty_authorized_keys | :invalid_public_key | :invalid_encrypted_key}
  def validate_format(%__MODULE__{secret: ""}), do: {:error, :empty_secret}

  def validate_format(%__MODULE__{authorized_keys: authorized_keys})
      when map_size(authorized_keys) == 0,
      do: {:error, :empty_authorized_keys}

  def validate_format(%__MODULE__{authorized_keys: authorized_keys}) do
    Enum.reduce_while(authorized_keys, :ok, fn {public_key, encrypted_key}, _acc ->
      with :ok <- validate_public_key(public_key),
           :ok <- validate_encrypted_key(public_key, encrypted_key) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp validate_public_key(public_key) do
    if Crypto.valid_public_key?(public_key) do
      :ok
    else
      {:error, :invalid_public_key}
    end
  end

  defp validate_encrypted_key(<<0::8, _rest::binary>>, <<_encrypted_key::binary-80>>), do: :ok
  defp validate_encrypted_key(_public_key, <<_encrypted_key::binary-113>>), do: :ok
  defp validate_encrypted_key(_, _), do: {:error, :invalid_encrypted_key}
end
