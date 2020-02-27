defmodule UnirisChain.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  alias __MODULE__.NodeMovements
  alias __MODULE__.LedgerMovements
  alias UnirisCrypto, as: Crypto

  @enforce_keys [
    :proof_of_integrity,
    :proof_of_work,
    :ledger_movements,
    :node_movements,
    :signature
  ]
  defstruct [
    :proof_of_integrity,
    :proof_of_work,
    :ledger_movements,
    :node_movements,
    :signature
  ]

  @typedoc """
  Validation performed by a coordinator:
  - Proof of work: results of the verification from the list of origin public keys matching the origin signature
  - Proof of integrity: Integry proof of the entire transaction chain
  - NodeMovements: fee and node include inside the rewards
  - LedgerMovements: UTXO movements (previous ledger and next ledger)
  - Signature: generated from the coordinator private key to avoid non-repudidation of the stamp
  """
  @type t :: %__MODULE__{
          proof_of_integrity: binary(),
          proof_of_work: binary(),
          node_movements: NodeMovements.t(),
          ledger_movements: LedgerMovements.t(),
          signature: binary()
        }

  @doc """
  Create a new signed validation stamp
  """
  @spec new(binary(), binary(), LedgerMovements.t(), NodeMovements.t()) :: __MODULE__.t()
  def new(
        proof_of_work,
        proof_of_integrity,
        ledger_movements = %LedgerMovements{},
        node_movements = %NodeMovements{}
      ) do
    stamp = %{
      proof_of_work: proof_of_work,
      proof_of_integrity: proof_of_integrity,
      ledger_movements: ledger_movements,
      node_movements: node_movements
    }

    sig = Crypto.sign(stamp, with: :node, as: :last)
    struct(__MODULE__, Map.put(stamp, :signature, sig))
  end

  @doc """
  Verify if the validation stamp signature is valid
  """
  def valid_signature?(stamp = %__MODULE__{signature: sig}, public_key) do
    Crypto.verify(
      sig,
      Map.take(stamp, [:proof_of_work, :proof_of_integrity, :ledger_movements, :node_movements]),
      public_key
    )
  end
end
