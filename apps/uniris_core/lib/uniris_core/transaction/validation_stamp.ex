defmodule UnirisCore.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  alias __MODULE__.NodeMovements
  alias __MODULE__.LedgerMovements
  alias UnirisCore.Crypto

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
  - Proof of work: Origin public key matching the origin signature
  - Proof of integrity: Integry proof of the entire transaction chain
  - NodeMovements: fee and node include inside the rewards
  - LedgerMovements: UTXO movements (previous ledger and next ledger)
  - Signature: generated from the coordinator private key to avoid non-repudidation of the stamp
  """
  @type t :: %__MODULE__{
          proof_of_integrity: binary(),
          proof_of_work: Crypto.key(),
          node_movements: NodeMovements.t(),
          ledger_movements: LedgerMovements.t(),
          signature: binary()
        }

  @spec new(
          proof_of_work :: Crypto.key(),
          proof_of_integrity :: binary(),
          node_movements :: NodeMovements.t(),
          ledger_movements :: LedgerMovements.t()
        ) :: __MODULE__.t()
  def new(pow, poi, node_movements = %NodeMovements{}, ledger_movements = %LedgerMovements{})
      when is_binary(pow) and is_binary(poi) do
    data = %{
      proof_of_work: pow,
      proof_of_integrity: poi,
      node_movements: node_movements,
      ledger_movements: ledger_movements
    }

    signature = Crypto.sign_with_node_key(data)
    struct!(__MODULE__, Map.put(data, :signature, signature))
  end

  @spec valid_signature?(
          stamp :: __MODULE__.t(),
          coordinator_public_key :: Crypto.key()
        ) :: boolean()
  def valid_signature?(stamp = %__MODULE__{}, coordinator_public_key)
      when is_binary(coordinator_public_key) do
    Crypto.verify(
      stamp.signature,
      Map.take(stamp, [:proof_of_work, :proof_of_integrity, :ledger_movements, :node_movements]),
      coordinator_public_key
    )
  end
end
