defmodule UnirisValidation.ProofOfWork do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisNetwork, as: Network
  alias UnirisCrypto, as: Crypto

  @doc """
  Execute the proof of work by scan all the origin public keys and try to found out which one
  matches the origin signature of the transaction:

  Returns `{:error, :not_found}` when no keys successed in the signature verification
  """
  def run(tx = %Transaction{}) do
    check_public_key(
      tx.origin_signature,
      Map.take(tx, [
        :address,
        :type,
        :timestamp,
        :data,
        :previous_public_key,
        :previous_signature
      ]),
      Network.origin_public_keys()
    )
  end

  ## Check recursively all the public key with the origin signature.
  ## Once the public key is found, the iteration is stopped
  @spec check_public_key(binary(), map(), list(binary())) ::
          {:ok, binary()} | {:error, :not_found}
  defp check_public_key(sig, data, [public_key | rest]) do
    if Crypto.verify(sig, data, public_key) do
      {:ok, public_key}
    else
      check_public_key(sig, data, rest)
    end
  end

  defp check_public_key(_sig, _data, []), do: {:error, :not_found}

  defp check_public_key(sig, data, public_key) do
    if Crypto.verify(sig, data, public_key) do
      {:ok, public_key}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Verify the proof of work of the validation stamp

  If the proof of work is empty meaning it's not has been found any valid public key,
  hence, the POW algorithm is performed to recheck if there is no origin public keys which match the transaction's origin signature
  """
  @spec verify(Transaction.pending(), binary()) :: boolean()
  def verify(tx = %Transaction{}, "") do
    case run(tx) do
      {:ok, _} ->
        false

      {:error, :not_found} ->
        true
    end
  end

  def verify(tx = %Transaction{}, pow) do
    Crypto.verify(
      tx.origin_signature,
      Map.take(tx, [
        :address,
        :type,
        :timestamp,
        :data,
        :previous_public_key,
        :previous_signature
      ]),
      pow
    )
  end
end
