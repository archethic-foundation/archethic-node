defmodule ArchEthic.TransactionChain.TransactionData.Keys do
  @moduledoc """
  Represents section in the transaction data to store secrets and authorized keys to
  read the encrypted secrets.
  """
  defstruct authorized_keys: [], secrets: []

  alias ArchEthic.Crypto

  @type t :: %__MODULE__{
          secrets: list(binary()),
          authorized_keys: list(%{(public_key :: Crypto.key()) => encrypted_key :: binary()})
        }

  @doc """
  Add a secret with its authorized keys

  ## Examples

      iex> secret_key = :crypto.strong_rand_bytes(32)
      iex> secret = "important message"
      iex> {pub, _pv} = Crypto.generate_deterministic_keypair("seed")
      iex> %Keys{authorized_keys: [authorized_keys] } = Keys.add_secret(%Keys{}, secret, secret_key, [pub])
      iex> Map.keys(authorized_keys)
      [
        <<0, 0, 241, 101, 225, 229, 247, 194, 144, 229, 47, 46, 222, 243, 251, 171, 96, 203, 174, 116, 191, 211, 
        39, 79, 142, 94, 225, 222, 51, 69, 201, 84, 161,102>>
      ]
  """
  @spec add_secret(
          t(),
          secret :: binary(),
          secret_key :: binary(),
          authorized_public_keys :: list(Crypto.key())
        ) :: t()
  def add_secret(keys = %__MODULE__{}, secret, secret_key, authorized_public_keys)
      when is_binary(secret) and is_binary(secret_key) and is_list(authorized_public_keys) do
    keys
    |> Map.update!(:secrets, &(&1 ++ [secret]))
    |> Map.update!(:authorized_keys, fn encrypted_keys ->
      new_encrypted_keys =
        Enum.map(authorized_public_keys, fn public_key ->
          {public_key, Crypto.ec_encrypt(secret_key, public_key)}
        end)
        |> Enum.into(%{})

      encrypted_keys ++ [new_encrypted_keys]
    end)
  end

  @doc """
  Serialize the transaction data keys

  ## Examples

      iex> %Keys{
      ...>   secrets: [<<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>],
      ...>   authorized_keys: [%{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
      ...>   }]
      ...> }
      ...> |> Keys.serialize()
      <<
        # Nb of secrets
        1,
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
  def serialize(%__MODULE__{secrets: []}), do: <<0>>

  def serialize(%__MODULE__{secrets: secrets, authorized_keys: authorized_keys})
      when length(secrets) == length(authorized_keys) do
    secrets_bin =
      Enum.map(secrets, fn secret ->
        <<byte_size(secret)::32, secret::binary>>
      end)
      |> :erlang.list_to_binary()

    authorized_keys_bin =
      Enum.map(authorized_keys, fn keys_by_secret ->
        authorized_keys_bin =
          Enum.map(keys_by_secret, fn {public_key, encrypted_key} ->
            <<public_key::binary, encrypted_key::binary>>
          end)
          |> :erlang.list_to_binary()

        <<map_size(keys_by_secret)::8, authorized_keys_bin::binary>>
      end)
      |> :erlang.list_to_binary()

    <<length(secrets)::8, secrets_bin::binary, authorized_keys_bin::binary>>
  end

  @doc """
  Deserialize a transaction data keys encoded

  ## Examples

      iex> <<1, 0, 0, 0, 16, 205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206,
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
          secrets: [<<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>],
          authorized_keys: [%{
            <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
            83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
              <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
                177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
                233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
                212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
                224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
          }]
        },
        <<>>
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<nb_secrets::8, rest::bitstring>>) do
    {secrets, rest} = reduce_secrets_bin(rest, nb_secrets, [])
    {authorized_keys, rest} = reduce_authorized_keys_bin(rest, nb_secrets, [])

    {%__MODULE__{
       secrets: secrets,
       authorized_keys: authorized_keys
     }, rest}
  end

  defp reduce_secrets_bin(rest, 0, _), do: {[], rest}

  defp reduce_secrets_bin(rest, nb_secrets, acc) when length(acc) == nb_secrets,
    do: {Enum.reverse(acc), rest}

  defp reduce_secrets_bin(
         <<secret_size::32, secret::binary-size(secret_size), rest::bitstring>>,
         nb_secrets,
         acc
       ) do
    reduce_secrets_bin(rest, nb_secrets, [secret | acc])
  end

  defp reduce_authorized_keys_bin(rest, 0, _acc), do: {[], rest}

  defp reduce_authorized_keys_bin(rest, nb_secrets, acc) when length(acc) == nb_secrets,
    do: {Enum.reverse(acc), rest}

  defp reduce_authorized_keys_bin(<<nb_authorized_keys::8, rest::binary>>, nb_secrets, acc) do
    {authorized_keys, rest} = do_reduce_authorized_keys_bin(rest, nb_authorized_keys, %{})
    reduce_authorized_keys_bin(rest, nb_secrets, [authorized_keys | acc])
  end

  defp do_reduce_authorized_keys_bin(rest, 0, _), do: {[], rest}

  defp do_reduce_authorized_keys_bin(rest, nb_authorized_keys, acc)
       when map_size(acc) == nb_authorized_keys,
       do: {acc, rest}

  defp do_reduce_authorized_keys_bin(
         <<0::8, origin_id::8, key::binary-32, encrypted_key::binary-size(80), rest::bitstring>>,
         nb_authorized_keys,
         acc
       ) do
    do_reduce_authorized_keys_bin(
      rest,
      nb_authorized_keys,
      Map.put(acc, <<0::8, origin_id::8, key::binary>>, encrypted_key)
    )
  end

  defp do_reduce_authorized_keys_bin(
         <<curve_id::8, origin_id::8, public_key::binary-65, encrypted_key::binary-113,
           rest::bitstring>>,
         nb_authorized_keys,
         acc
       )
       when curve_id in [1, 2] do
    do_reduce_authorized_keys_bin(
      rest,
      nb_authorized_keys,
      Map.put(acc, <<curve_id::8, origin_id::8, public_key::binary>>, encrypted_key)
    )
  end

  @spec from_map(map()) :: t()
  def from_map(keys = %{}) do
    %__MODULE__{
      secrets: Map.get(keys, :secrets, []),
      authorized_keys: Map.get(keys, :authorized_keys, [])
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{secrets: [], authorized_keys: []}
  end

  def to_map(keys = %__MODULE__{}) do
    %{
      secrets: Map.get(keys, :secrets, []),
      authorized_keys: Map.get(keys, :authorized_keys, [])
    }
  end

  @doc """
  Determine if the a public key is register inside the authorized public key

  ## Examples

      iex> %Keys{
      ...>   secrets: [<<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>],
      ...>   authorized_keys: [%{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }]
      ...> }
      ...> |> Keys.authorized_key?(<<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...> 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>)
      true
  """
  @spec authorized_key?(t(), Crypto.key()) :: boolean()
  def authorized_key?(%__MODULE__{authorized_keys: auth_keys}, node_public_key)
      when is_binary(node_public_key) do
    Enum.any?(auth_keys, fn auth_keys_by_secret ->
      Map.has_key?(auth_keys_by_secret, node_public_key)
    end)
  end

  @doc """
  List the authorized public keys for a given secret index

  ## Examples

      iex> %Keys{
      ...>   secrets: [<<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>],
      ...>   authorized_keys: [%{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }]
      ...> }
      ...> |> Keys.list_authorized_public_keys_at(0)
      [
        <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
          83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>
      ]
  """
  @spec list_authorized_public_keys_at(t(), non_neg_integer()) :: list(Crypto.key())
  def list_authorized_public_keys_at(%__MODULE__{authorized_keys: auth_keys}, secret_index)
      when is_integer(secret_index) and secret_index >= 0 do
    auth_keys
    |> Enum.at(secret_index)
    |> Map.keys()
  end

  @doc """
  List all the authorized keys

  ## Examples

      iex> %Keys{
      ...>   secrets: [<<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>],
      ...>   authorized_keys: [%{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }]
      ...> }
      ...> |> Keys.list_authorized_public_keys()
      [
        <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
          83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>
      ]
  """
  @spec list_authorized_public_keys(t()) :: list(Crypto.key())
  def list_authorized_public_keys(%__MODULE__{authorized_keys: auth_keys}) do
    Enum.flat_map(auth_keys, &Map.keys(&1))
  end

  @doc """
  Get the encrypted key from the authorized public key to decrypt the secret

  ## Examples

      iex> %Keys{
      ...>   secrets: [<<205, 124, 251, 211, 28, 69, 249, 1, 58, 108, 16, 35, 23, 206, 198, 202>>],
      ...>   authorized_keys: [%{
      ...>      <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...>         83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
      ...>      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
      ...>        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
      ...>        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
      ...>        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
      ...>        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
      ...>   }]
      ...> }
      ...> |> Keys.get_encrypted_key_at(0, <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
      ...> 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>>)
      <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
        177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
        233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
        212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
        224, 214, 225, 146, 44, 83, 111, 34, 239, 99, 1, 126, 241, 246>>
  """
  @spec get_encrypted_key_at(
          t(),
          secret_index :: non_neg_integer(),
          authorized_public_key :: Crypto.key()
        ) :: binary()
  def get_encrypted_key_at(%__MODULE__{authorized_keys: auth_keys}, secret_index, public_key)
      when is_integer(secret_index) and secret_index >= 0 and is_binary(public_key) do
    auth_keys
    |> Enum.at(secret_index)
    |> Map.get(public_key)
  end
end
