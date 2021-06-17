defmodule Uniris.Crypto.ID do
  @moduledoc false

  alias Uniris.Crypto

  @doc """
  Get an identification from a elliptic curve name

  ## Examples

      iex> ID.from_curve(:ed25519)
      0

      iex> ID.from_curve(:secp256r1)
      1
  """
  @spec from_curve(Crypto.supported_curve()) :: integer()
  def from_curve(:ed25519), do: 0
  def from_curve(:secp256r1), do: 1
  def from_curve(:secp256k1), do: 2

  @doc """
  Get a curve name from an curve ID

  ## Examples

      iex> ID.to_curve(0)
      :ed25519

      iex> ID.to_curve(1)
      :secp256r1
  """
  @spec to_curve(integer()) :: Crypto.supported_curve()
  def to_curve(0), do: :ed25519
  def to_curve(1), do: :secp256r1
  def to_curve(2), do: :secp256k1

  @doc """
  Get an identification from an hash algorithm

  ## Examples

      iex> ID.from_hash(:sha256)
      0

      iex> ID.from_hash(:blake2b)
      4
  """
  @spec from_hash(Crypto.supported_hash()) :: integer()
  def from_hash(:sha256), do: 0
  def from_hash(:sha512), do: 1
  def from_hash(:sha3_256), do: 2
  def from_hash(:sha3_512), do: 3
  def from_hash(:blake2b), do: 4

  @doc """
  Get an identification from a key origin

  ## Examples

      iex> ID.from_origin(:software)
      0

      iex> ID.from_origin(:tpm)
      1
  """
  @spec from_origin(Crypto.supported_origin()) :: integer()
  def from_origin(:software), do: 0
  def from_origin(:tpm), do: 1

  @doc """
  Get a origin from an identification
  """
  @spec to_origin(integer()) :: Crypto.supported_origin()
  def to_origin(0), do: :software
  def to_origin(1), do: :tpm

  @doc """
  Prepend hash by the algorithm identification byte

  ## Examples

      iex> ID.prepend_hash(<<67, 114, 249, 17, 148, 8, 100, 233, 130, 249, 233, 179, 216, 18, 36, 222, 187,
      ...> 161, 212, 202, 143, 54, 45, 141, 99, 144, 171, 133, 137, 173, 211, 126>>, :sha256)
      <<0, 67, 114, 249, 17, 148, 8, 100, 233, 130, 249, 233, 179, 216, 18, 36, 222, 187,
      161, 212, 202, 143, 54, 45, 141, 99, 144, 171, 133, 137, 173, 211, 126>>
  """
  @spec prepend_hash(binary(), Crypto.supported_hash()) :: <<_::8, _::_*8>>
  def prepend_hash(hash, algorithm) do
    <<from_hash(algorithm)::8, hash::binary>>
  end

  @doc """
  Prepend each keys by the identifying curve and the origin

  ## Examples

      iex> ID.prepend_keypair({
      ...> <<38, 59, 8, 1, 172, 20, 74, 63, 15, 72, 206, 129, 140, 212, 188, 102, 203, 51,
      ...>   188, 207, 135, 134, 211, 3, 87, 148, 178, 162, 118, 208, 109, 96>>,
      ...> <<21, 150, 237, 25, 119, 159, 16, 128, 43, 48, 169, 243, 214, 246, 102, 147,
      ...>   172, 79, 60, 159, 89, 230, 31, 254, 187, 176, 70, 166, 119, 96, 87, 194>>
      ...> }, :ed25519)
      {
        <<0, 0, 38, 59, 8, 1, 172, 20, 74, 63, 15, 72, 206, 129, 140, 212, 188, 102, 203, 51,
          188, 207, 135, 134, 211, 3, 87, 148, 178, 162, 118, 208, 109, 96>>,
        <<0, 0, 21, 150, 237, 25, 119, 159, 16, 128, 43, 48, 169, 243, 214, 246, 102, 147,
          172, 79, 60, 159, 89, 230, 31, 254, 187, 176, 70, 166, 119, 96, 87, 194>>
      }
  """
  @spec prepend_keypair(
          {binary(), binary()},
          Crypto.supported_curve(),
          Crypto.supported_origin()
        ) ::
          {Crypto.key(), Crypto.key()}
  def prepend_keypair({public_key, private_key}, curve, origin \\ :software) do
    {prepend_key(public_key, curve, origin), prepend_key(private_key, curve, origin)}
  end

  @doc """
  Prepend key by identifying the curve and the origin
  """
  @spec prepend_key(binary(), Crypto.supported_curve(), Crypto.supported_origin()) :: Crypto.key()
  def prepend_key(key, curve, origin \\ :software) do
    curve_id = from_curve(curve)
    origin_id = from_origin(origin)

    <<curve_id::8, origin_id::8, key::binary>>
  end
end
