defmodule UnirisCore.Mining.ProofOfIntegrity do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Crypto

  def compute([tx = %Transaction{} | []]) do
    from_transaction(tx)
  end

  def compute([
        tx = %Transaction{}
        | [
            %Transaction{
              validation_stamp: %ValidationStamp{proof_of_integrity: previous_poi}
            }
            | _
          ]
      ]) do
    Crypto.hash([from_transaction(tx), previous_poi])
  end

  defp from_transaction(tx = %Transaction{}) do
    Crypto.hash(
      Map.take(tx, [
        :address,
        :type,
        :timestamp,
        :data,
        :previous_public_key,
        :previous_signature,
        :origin_signature
      ])
    )
  end
end
