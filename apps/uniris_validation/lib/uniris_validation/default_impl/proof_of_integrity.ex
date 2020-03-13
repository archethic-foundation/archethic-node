defmodule UnirisValidation.DefaultImpl.ProofOfIntegrity do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisCrypto, as: Crypto

  @doc """
  Compute the proof of integrity based on a transaction and previous transaction chain

  Taking the hash of the transaction and the previous transaction proof of integrity.
  These two value are hashed to produce the proof of integrity.

  ## Examples

     iex> tx = %UnirisChain.Transaction{
     ...>  address: "22E75791BCAF3B12FAEDECA3432994129152857E69F5B9129D588E4AC9B1969B",
     ...>  type: :transfer,
     ...>  timestamp: 1582132275,
     ...>  data: %{},
     ...>  previous_public_key: "",
     ...>  previous_signature: "",
     ...>  origin_signature: ""
     ...> }
     iex> previous_chain = [Map.put(tx, :validation_stamp, %UnirisChain.Transaction.ValidationStamp{
     ...>   proof_of_work: "",
     ...>   ledger_movements: %UnirisChain.Transaction.ValidationStamp.LedgerMovements{},
     ...>   node_movements: %UnirisChain.Transaction.ValidationStamp.NodeMovements{fee: 1, rewards: []},
     ...>   proof_of_integrity: "B83DAC77B813006F94CEEF73565BD211E327CB8D1C23A0A1390A4AE180991D38",
     ...>   signature: ""
     ...> })]
     iex> UnirisValidation.DefaultImpl.ProofOfIntegrity.from_chain([tx | previous_chain])
     <<0, 249, 178, 39, 230, 117, 84, 68, 85, 148, 134, 163, 72, 186, 98,
     216, 60, 205, 65, 15, 190, 58, 161, 61, 110, 24, 180, 5, 105, 151,
     75, 99, 60>>
  """

  def from_chain([
        tx = %Transaction{}
        | [
            %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: previous_poi}}
            | _rest
          ]
      ]) do
    Crypto.hash([from_transaction(tx), previous_poi])
  end

  def from_chain([tx = %Transaction{} | []]) do
    from_transaction(tx)
  end

  def from_transaction(tx = %Transaction{}) do
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
