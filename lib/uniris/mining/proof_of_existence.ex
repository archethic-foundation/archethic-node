defmodule Uniris.Mining.ProofOfExistence do
  @moduledoc false

  alias Uniris.Oracles.TransactionContent

  alias Uniris.TransactionChain.{
    Transaction,
    TransactionData
  }

  # Public

  @spec do_proof_of_existence(Transaction.t()) :: boolean()
  def do_proof_of_existence(tx) do
    %TransactionData{content: content} = tx.data
    %TransactionContent{mfa: {m, f, a}, payload: payload} = :erlang.binary_to_term(content)

    response =
      apply(m, f, a)
      |> List.first()

    payload_hash = hash(payload)
    response_hash = hash(response)
    String.equivalent?(payload_hash, response_hash)
  end

  # Private

  @spec hash(String.t()) :: String.t()
  defp hash(payload) do
    :md5
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end
end
