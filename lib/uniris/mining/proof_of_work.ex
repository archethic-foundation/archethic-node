defmodule Uniris.Mining.ProofOfWork do
  @moduledoc """
  Handle the Proof Of Work algorithm.

  The Proof Of Work algorithm is composed of the:
  - retrieval of shared origin public keys
  - search of the public key by scanning them

  Transaction origin public keys can change depends on the type of transaction or the level of security required.
  """

  alias Uniris.Contracts
  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Conditions

  alias Uniris.Crypto

  alias Uniris.P2P

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  @doc """
  Scan a list of public keys to determine which one matches the transaction's origin signature.

  Once the match is made, the scan is stopped.
  At the end of the scan, if not public keys has matched the origin signature, return an `{:error, :not_found}` tuple

  ## Examples

      iex> [
      ...>   <<0, 108, 152, 237, 14, 218, 24, 75, 159, 187, 112, 249, 209, 182, 108, 133,
      ...>     205, 141, 147, 182, 218, 85, 60, 169, 137, 238, 140, 254, 84, 21, 209, 210,
      ...>     85>>,
      ...>   <<0, 8, 138, 54, 218, 150, 70, 180, 4, 53, 144, 77, 115, 198, 46, 128, 207,
      ...>     223, 189, 95, 253, 38, 40, 243, 54, 27, 96, 70, 86, 220, 217, 9, 1>>,
      ...>   <<0, 211, 80, 49, 147, 126, 126, 253, 230, 87, 77, 68, 164, 77, 212, 75, 123,
      ...>     37, 92, 251, 236, 251, 102, 255, 147, 203, 168, 147, 192, 65, 28, 13, 13>>,
      ...>   <<1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45, 39, 145,
      ...>     188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153, 28, 60, 179, 54,
      ...>     132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47, 115, 198, 152, 151, 190,
      ...>     95, 48, 29, 233, 166, 53, 33, 160, 138, 196, 239, 52, 193, 135, 40>>,
      ...>   <<0, 156, 198, 40, 89, 184, 32, 101, 103, 168, 90, 234, 89, 93, 170, 89, 45,
      ...>     100, 237, 251, 223, 10, 130, 88, 124, 15, 21, 74, 28, 33, 245, 142, 179>>,
      ...>   <<0, 25, 36, 103, 151, 183, 40, 176, 220, 225, 176, 57, 61, 203, 57, 118, 134,
      ...>     150, 41, 194, 35, 35, 160, 145, 98, 31, 36, 154, 209, 151, 12, 125, 142>>
      ...> ]
      ...> |> ProofOfWork.find_transaction_origin_public_key(%Transaction{
      ...>    address: <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143,
      ...>      71, 189, 178, 226, 124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168,
      ...>      248, 14, 164>>,
      ...>    data: %TransactionData{},
      ...>    origin_signature: <<48, 69, 2, 32, 100, 68, 24, 152, 22, 179, 225, 12, 27, 199, 0, 108, 149, 4,
      ...>      94, 224, 213, 155, 246, 10, 255, 129, 201, 84, 111, 112, 230, 87, 27, 196, 6,
      ...>      151, 2, 33, 0, 203, 90, 84, 191, 11, 233, 89, 221, 1, 42, 226, 95, 203, 57,
      ...>      52, 27, 45, 111, 195, 84, 222, 50, 35, 177, 214, 10, 253, 10, 64, 117, 114,
      ...>      84>>,
      ...>    previous_public_key: <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210,
      ...>      50, 138, 25, 142, 130, 140, 51, 143, 208, 228, 230, 150, 84, 161, 157, 32,
      ...>      42, 55, 118, 226, 12>>,
      ...>    previous_signature: <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7,
      ...>      254, 45, 155, 16, 93, 218, 167, 254, 192, 171, 72, 45, 35, 228, 190, 53, 99,
      ...>      157, 186, 69, 123, 129, 107, 234, 129, 135, 115, 243, 177, 225, 166, 248,
      ...>      247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253, 6, 210, 81, 143, 0,
      ...>      118, 222, 15>>,
      ...>    type: :transfer
      ...>  })
      {
        :ok,
        # The 4th public key matches
        <<1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45, 39, 145,
          188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153, 28, 60, 179, 54,
          132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47, 115, 198, 152, 151, 190,
          95, 48, 29, 233, 166, 53, 33, 160, 138, 196, 239, 52, 193, 135, 40>>
      }
  """
  @spec find_transaction_origin_public_key(list(Crypto.key()), Transaction.t()) ::
          {:ok, Crypto.key()} | {:error, :not_found}
  def find_transaction_origin_public_key(
        origin_public_keys,
        tx = %Transaction{origin_signature: origin_signature}
      )
      when is_list(origin_public_keys) do
    tx
    |> Transaction.extract_for_origin_signature()
    |> Transaction.serialize()
    |> do_find_transaction_origin_public_key(origin_signature, origin_public_keys)
  end

  defp do_find_transaction_origin_public_key(data, sig, [public_key | rest]) do
    if Crypto.verify(sig, data, public_key) do
      {:ok, public_key}
    else
      do_find_transaction_origin_public_key(data, sig, rest)
    end
  end

  defp do_find_transaction_origin_public_key(_data, _sig, []), do: {:error, :not_found}

  @doc """
  List the origin public keys candidates for a given transaction (default: all the origin public keys)

  Smart contract code can defined which family to use (like security level)
  """
  @spec list_origin_public_keys_candidates(Transaction.t()) :: list(Crypto.key())
  def list_origin_public_keys_candidates(%Transaction{data: %TransactionData{code: code}})
      when code != "" do
    %Contract{conditions: %Conditions{origin_family: family}} = Contracts.parse!(code)

    case family do
      nil ->
        SharedSecrets.list_origin_public_keys()

      family ->
        SharedSecrets.list_origin_public_keys(family)
    end
  end

  def list_origin_public_keys_candidates(%Transaction{
        type: :node,
        previous_public_key: previous_key
      }) do
    case TransactionChain.get_first_public_key(previous_key) do
      ^previous_key ->
        [previous_key]

      _ ->
        P2P.list_authorized_public_keys()
    end
  end

  def list_origin_public_keys_candidates(%Transaction{type: :node_shared_secrets}) do
    P2P.list_authorized_public_keys()
  end

  def list_origin_public_keys_candidates(%Transaction{}),
    do: SharedSecrets.list_origin_public_keys()
end
