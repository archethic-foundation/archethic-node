defmodule UnirisCore.Crypto.ID do
  @moduledoc false

  @doc """
  Get an identification from a elliptic curve name
  """
  @spec id_from_curve(UnirisCore.Crypto.supported_curve()) :: integer()
  def id_from_curve(:ed25519), do: 0
  def id_from_curve(:secp256r1), do: 1
  def id_from_curve(:secp256k1), do: 2

  @doc """
  Get a curve name from an curve ID
  """
  @spec curve_from_id(integer()) :: UnirisCore.Crypto.supported_curve()
  def curve_from_id(0), do: :ed25519
  def curve_from_id(1), do: :secp256r1
  def curve_from_id(2), do: :secp256k1

  @doc """
  Get an identification from an hash algorithm
  """
  @spec id_from_hash(UnirisCore.Crypto.supported_hash()) :: integer()
  def id_from_hash(:sha256), do: 0
  def id_from_hash(:sha512), do: 1
  def id_from_hash(:sha3_256), do: 2
  def id_from_hash(:sha3_512), do: 3
  def id_from_hash(:blake2b), do: 4

  @spec identify_keypair({binary(), binary()}, integer()) ::
          {UnirisCore.Crypto.key(), UnirisCore.Crypto.key()}
  def identify_keypair({public_key, private_key}, id) do
    {
      [<<id::8>>, public_key] |> :binary.list_to_bin(),
      [<<id::8>>, private_key] |> :binary.list_to_bin()
    }
  end

  @spec identify_hash(binary(), integer()) :: <<_::8, _::_*8>>
  def identify_hash(hash, id) do
    [<<id::8>>, hash] |> :binary.list_to_bin()
  end
end
