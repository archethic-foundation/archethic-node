defmodule UnirisCrypto.ID do
  @moduledoc false

  @spec get_id_from_curve(Crypto.supported_curve()) :: {:ok, integer()} | {:error, :invalid_curve}
  def get_id_from_curve(curve) when is_atom(curve) do
    case Enum.find_index(Application.get_env(:uniris_crypto, :supported_curves), &(&1 == curve)) do
      nil ->
        {:error, :invalid_curve}

      curve_id ->
        {:ok, curve_id}
    end
  end

  @spec get_curve_from_id(integer()) :: {:ok, Crypto.supported_curve()} | {:error, :invalid_curve}
  def get_curve_from_id(id) when is_integer(id) do
    case Enum.at(Application.get_env(:uniris_crypto, :supported_curves), id) do
      nil ->
        {:error, :invalid_curve}

      curve ->
        {:ok, curve}
    end
  end

  def get_id_from_hash(hash_algo) when is_atom(hash_algo) do
    case Enum.find_index(
           Application.get_env(:uniris_crypto, :supported_hashes),
           &(&1 == hash_algo)
         ) do
      nil ->
        {:error, :invalid_hash_algo}

      id ->
        {:ok, id}
    end
  end
end
