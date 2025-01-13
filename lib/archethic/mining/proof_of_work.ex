defmodule Archethic.Mining.ProofOfWork do
  @moduledoc """
  Handle the Proof Of Work algorithm.

  The Proof Of Work algorithm is composed of the:
  - retrieval of shared origin public keys
  - search of the public key by scanning them

  Transaction origin public keys can change depends on the type of transaction or the level of security required.
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Contract, as: InterpretedContract

  alias Archethic.Crypto

  alias Archethic.P2P.Node

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  @doc """
  Scan a list of public keys to determine which one matches the transaction's origin signature.

  Once the match is made, the scan is stopped.
  At the end of the scan, if not public keys has matched the origin signature, return an `{:error, :not_found}` tuple

  ## Examples

      iex> [
      ...>   <<0, 0, 108, 152, 237, 14, 218, 24, 75, 159, 187, 112, 249, 209, 182, 108, 133, 205,
      ...>     141, 147, 182, 218, 85, 60, 169, 137, 238, 140, 254, 84, 21, 209, 210, 85>>,
      ...>   <<0, 0, 8, 138, 54, 218, 150, 70, 180, 4, 53, 144, 77, 115, 198, 46, 128, 207, 223,
      ...>     189, 95, 253, 38, 40, 243, 54, 27, 96, 70, 86, 220, 217, 9, 1>>,
      ...>   <<0, 0, 211, 80, 49, 147, 126, 126, 253, 230, 87, 77, 68, 164, 77, 212, 75, 123, 37,
      ...>     92, 251, 236, 251, 102, 255, 147, 203, 168, 147, 192, 65, 28, 13, 13>>,
      ...>   <<0, 0, 241, 101, 225, 229, 247, 194, 144, 229, 47, 46, 222, 243, 251, 171, 96, 203,
      ...>     174, 116, 191, 211, 39, 79, 142, 94, 225, 222, 51, 69, 201, 84, 161, 102>>,
      ...>   <<0, 0, 156, 198, 40, 89, 184, 32, 101, 103, 168, 90, 234, 89, 93, 170, 89, 45, 100,
      ...>     237, 251, 223, 10, 130, 88, 124, 15, 21, 74, 28, 33, 245, 142, 179>>,
      ...>   <<0, 0, 25, 36, 103, 151, 183, 40, 176, 220, 225, 176, 57, 61, 203, 57, 118, 134, 150,
      ...>     41, 194, 35, 35, 160, 145, 98, 31, 36, 154, 209, 151, 12, 125, 142>>
      ...> ]
      ...> |> ProofOfWork.find_transaction_origin_public_key(%Transaction{
      ...>   address:
      ...>     <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178,
      ...>       226, 124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      ...>   data: %TransactionData{},
      ...>   origin_signature:
      ...>     <<196, 90, 51, 177, 4, 254, 153, 69, 234, 109, 249, 83, 185, 77, 130, 174, 53, 210,
      ...>       46, 101, 70, 248, 234, 37, 245, 50, 46, 84, 148, 171, 166, 189, 115, 70, 183, 73,
      ...>       66, 234, 101, 8, 109, 4, 125, 168, 170, 112, 13, 140, 93, 202, 251, 131, 151, 164,
      ...>       55, 100, 57, 192, 37, 154, 242, 14, 226, 12>>,
      ...>   previous_public_key:
      ...>     <<0, 0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130,
      ...>       140, 51, 143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      ...>   previous_signature:
      ...>     <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218,
      ...>       167, 254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234,
      ...>       129, 135, 115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209,
      ...>       223, 139, 253, 6, 210, 81, 143, 0, 118, 222, 15>>,
      ...>   type: :transfer
      ...> })
      {
        :ok,
        # The 4th public key matches
        <<0, 0, 241, 101, 225, 229, 247, 194, 144, 229, 47, 46, 222, 243, 251, 171, 96, 203, 174,
          116, 191, 211, 39, 79, 142, 94, 225, 222, 51, 69, 201, 84, 161, 102>>
      }
  """
  @spec find_transaction_origin_public_key(list(Crypto.key()), Transaction.t()) ::
          {:ok, Crypto.key()} | {:error, :not_found}
  def find_transaction_origin_public_key(
        origin_public_keys,
        tx = %Transaction{origin_signature: origin_signature}
      )
      when is_list(origin_public_keys) do
    start = System.monotonic_time()

    pow =
      tx
      |> Transaction.extract_for_origin_signature()
      |> Transaction.serialize(:extended)
      |> do_find_transaction_origin_public_key(origin_signature, origin_public_keys)

    :telemetry.execute(
      [:archethic, :mining, :proof_of_work],
      %{
        duration: System.monotonic_time() - start
      },
      %{nb_keys: length(origin_public_keys)}
    )

    pow
  end

  defp do_find_transaction_origin_public_key(data, sig, [public_key | rest]) do
    if Crypto.verify?(sig, data, public_key) do
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
  # TODO: support WasmContract inherit conditions
  @spec list_origin_public_keys_candidates(Transaction.t()) :: list(Crypto.key())
  def list_origin_public_keys_candidates(tx = %Transaction{version: version}) when version < 4 do
    case Contracts.from_transaction(tx) do
      {:ok,
       %InterpretedContract{
         conditions: %{
           inherit: %Interpreter.Conditions{
             subjects: %Interpreter.Conditions.Subjects{origin_family: family}
           }
         }
       }}
      when family != :all ->
        SharedSecrets.list_origin_public_keys(family)

      _ ->
        do_list_origin_public_keys_candidates(tx)
    end
  end

  def list_origin_public_keys_candidates(tx = %Transaction{}),
    do: do_list_origin_public_keys_candidates(tx)

  defp do_list_origin_public_keys_candidates(%Transaction{
         type: :node,
         data: %TransactionData{
           content: content
         }
       }) do
    {:ok, _ip, _p2p_port, _http_port, _transport, _reward_address, origin_public_key,
     _origin_certificate, _mining_public_key} = Node.decode_transaction_content(content)

    [origin_public_key]
  end

  defp do_list_origin_public_keys_candidates(%Transaction{}) do
    SharedSecrets.list_origin_public_keys()
  end
end
