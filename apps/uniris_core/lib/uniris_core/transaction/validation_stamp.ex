defmodule UnirisCore.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  alias __MODULE__.LedgerOperations
  alias UnirisCore.Transaction
  alias UnirisCore.Crypto
  alias UnirisCore.Mining.Fee
  alias UnirisCore.Mining.ProofOfWork
  alias UnirisCore.Mining.ProofOfIntegrity
  alias UnirisCore.Mining.Context

  @enforce_keys [
    :proof_of_integrity,
    :proof_of_work,
    :ledger_operations,
    :signature
  ]
  defstruct [
    :proof_of_integrity,
    :proof_of_work,
    :ledger_operations,
    :signature
  ]

  @typedoc """
  Validation performed by a coordinator:
  - Proof of work: Origin public key matching the origin signature
  - Proof of integrity: Integry proof of the entire transaction chain
  - Ledger Operations: Set of ledger operations taken by the network such as fee, node movements, transaction movements and unspent outputs
  - Signature: generated from the coordinator private key to avoid non-repudidation of the stamp
  """
  @type t :: %__MODULE__{
          proof_of_integrity: binary(),
          proof_of_work: Crypto.key(),
          ledger_operations: LedgerOperations.t(),
          signature: binary()
        }

  @doc """
  Create a new validation stamp based on a transaction, its context and the validation nodes
  to produce proofs of validations and the next UTXO ledger.
  """
  @spec new(
          Transaction.pending(),
          context :: Context.t(),
          welcome_node_public_key :: Crypto.key(),
          coordinator_public_key :: Crypto.key(),
          cross_validation_nodes :: list(Crypto.key())
        ) :: __MODULE__.t()
  def new(
        tx = %Transaction{},
        %Context{
          previous_chain: previous_chain,
          unspent_outputs: unspent_outputs,
          involved_nodes: previous_storage_node_public_keys
        },
        welcome_node_public_key,
        coordinator_public_key,
        cross_validation_node_public_keys
      ) do
    fee = Fee.compute(tx)

    node_movements =
      Fee.distribute(
        fee,
        welcome_node_public_key,
        coordinator_public_key,
        cross_validation_node_public_keys,
        previous_storage_node_public_keys
      )

    pow = ProofOfWork.find_origin_public_key(tx)
    poi = ProofOfIntegrity.compute([tx | previous_chain])

    ledger_operations = LedgerOperations.new!(tx, fee, unspent_outputs, node_movements)

    data = %{
      proof_of_work: pow,
      proof_of_integrity: poi,
      ledger_operations: ledger_operations
    }

    signature = Crypto.sign_with_node_key(data)
    struct!(__MODULE__, Map.put(data, :signature, signature))
  end

  @doc """
  Performs a series of checks to ensure the validity of the validation stamp
  and returns a list of inconsistencies
  """
  @spec inconsistencies(
          __MODULE__.t(),
          Transaction.validated(),
          coordinator_public_key :: Crypto.key(),
          cross_validation_node_public_keys :: list(Crypto.key()),
          context :: Context.t()
        ) ::
          inconsistencies :: [
            :signature | :proof_of_work | :proof_of_integrity | :ledger_operations
          ]
  def inconsistencies(
        stamp = %__MODULE__{
          proof_of_work: pow,
          proof_of_integrity: poi,
          ledger_operations: ledger_ops
        },
        tx = %Transaction{},
        coordinator_public_key,
        validation_nodes,
        %Context{
          unspent_outputs: unspent_outputs,
          previous_chain: previous_chain
        }
      ) do
    [
      {:signature, fn -> valid_signature?(stamp, coordinator_public_key) end},
      {:proof_of_work, fn -> ProofOfWork.verify?(pow, tx) end},
      {:proof_of_integrity,
       fn ->
         ProofOfIntegrity.verify?(poi, [tx | previous_chain])
       end},
      {:ledger_operations,
       fn ->
         LedgerOperations.verify?(
           ledger_ops,
           tx,
           unspent_outputs,
           validation_nodes
         )
       end}
    ]
    |> Enum.reject(fn {_, fun} -> fun.() == true end)
    |> Enum.map(fn {domain, _} -> domain end)
  end

  @doc """
  Verify the stamp signature using the coordinator public key
  """
  @spec valid_signature?(
          stamp :: __MODULE__.t(),
          coordinator_public_key :: Crypto.key()
        ) :: boolean()
  def valid_signature?(stamp = %__MODULE__{}, coordinator_public_key) do
    Crypto.verify(
      stamp.signature,
      Map.take(stamp, [
        :proof_of_work,
        :proof_of_integrity,
        :ledger_operations
      ]),
      coordinator_public_key
    )
  end
end
