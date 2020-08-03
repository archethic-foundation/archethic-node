defmodule Uniris.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  alias Uniris.Crypto

  alias Uniris.Mining.Context
  alias Uniris.Mining.Fee
  alias Uniris.Mining.ProofOfIntegrity
  alias Uniris.Mining.ProofOfWork

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations

  defstruct [
    :signature,
    :proof_of_work,
    :proof_of_integrity,
    :ledger_operations
  ]

  @type inconsistency() :: :signature | :proof_of_work | :proof_of_integrity | :ledger_operations

  @typedoc """
  Validation performed by a coordinator:
  - Proof of work: Origin public key matching the origin signature
  - Proof of integrity: Integry proof of the entire transaction chain
  - Ledger Operations: Set of ledger operations taken by the network such as fee, node movements, transaction movements and unspent outputs
  - Signature: generated from the coordinator private key to avoid non-repudidation of the stamp
  """
  @type t :: %__MODULE__{
          signature: binary(),
          proof_of_work: Crypto.key(),
          proof_of_integrity: binary(),
          ledger_operations: LedgerOperations.t()
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
        ) :: t()
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

    stamp = %__MODULE__{
      proof_of_work: pow,
      proof_of_integrity: poi,
      ledger_operations: ledger_operations
    }

    raw_stamp =
      stamp
      |> extract_for_signature
      |> serialize

    %{stamp | signature: Crypto.sign_with_node_key(raw_stamp)}
  end

  def extract_for_signature(%__MODULE__{
        proof_of_work: pow,
        proof_of_integrity: poi,
        ledger_operations: ops
      }) do
    %__MODULE__{
      proof_of_work: pow,
      proof_of_integrity: poi,
      ledger_operations: ops
    }
  end

  @doc """
  Performs a series of checks to ensure the validity of the validation stamp
  and returns a list of inconsistencies
  """
  @spec inconsistencies(
          t(),
          Transaction.t(),
          coordinator_public_key :: Crypto.key(),
          cross_validation_node_public_keys :: list(Crypto.key()),
          context :: Context.t()
        ) ::
          inconsistencies :: [inconsistency()]
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
          stamp :: t(),
          coordinator_public_key :: Crypto.key()
        ) :: boolean()
  def valid_signature?(stamp = %__MODULE__{}, coordinator_public_key) do
    raw_stamp =
      stamp
      |> extract_for_signature
      |> serialize

    Crypto.verify(
      stamp.signature,
      raw_stamp,
      coordinator_public_key
    )
  end

  @doc """
  Serialize a validation stamp info binary format

  ## Examples

     iex> Uniris.Transaction.ValidationStamp.serialize(%Uniris.Transaction.ValidationStamp{
     ...>   proof_of_work: <<0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
     ...>     155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206>>,
     ...>   proof_of_integrity: <<0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
     ...>     28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170>>,
     ...>   ledger_operations: %Uniris.Transaction.ValidationStamp.LedgerOperations{ fee: 0.1, transaction_movements: [], node_movements: [], unspent_outputs: []},
     ...>   signature: <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
     ...>     126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
     ...>     238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
     ...>     66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>
     ...> })
     <<
      # Proof of work
      0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
      155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,
      # Proof of integrity
      0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
      28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170,
      # Fee
      63, 185, 153, 153, 153, 153, 153, 154,
      # Nb of transaction movements
      0,
      # Nb of node movements
      0,
      # Nb of unspent outputs
      0,
      # Signature size,
      64,
      # Signature
      67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
      126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
      238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
      66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172
     >>
  """
  def serialize(%__MODULE__{
        proof_of_work: pow,
        proof_of_integrity: poi,
        ledger_operations: ledger_operations,
        signature: nil
      }) do
    <<pow::binary, poi::binary, LedgerOperations.serialize(ledger_operations)::binary>>
  end

  def serialize(%__MODULE__{
        proof_of_work: pow,
        proof_of_integrity: poi,
        ledger_operations: ledger_operations,
        signature: signature
      }) do
    <<pow::binary, poi::binary, LedgerOperations.serialize(ledger_operations)::binary,
      byte_size(signature)::8, signature::binary>>
  end

  @doc """
  Deserialize an encoded validation stamp

  ## Examples

      iex> <<0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
      ...> 155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,
      ...> 0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
      ...> 28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170,
      ...> 63, 185, 153, 153, 153, 153, 153, 154, 0, 0, 0, 64,
      ...> 67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
      ...> 126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
      ...> 238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
      ...> 66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>
      ...> |> Uniris.Transaction.ValidationStamp.deserialize()
      {
        %Uniris.Transaction.ValidationStamp{
          proof_of_work: <<0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
            155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,>>,
          proof_of_integrity: << 0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
            28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170>>,
          ledger_operations: %Uniris.Transaction.ValidationStamp.LedgerOperations{
            fee: 0.1,
            transaction_movements: [],
            node_movements: [],
            unspent_outputs: []
          },
          signature: <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
            126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
            238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
            66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>
        },
        ""
      }
  """
  def deserialize(<<curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), hash_id::8, rest::bitstring>> = rest
    hash_size = Crypto.hash_size(hash_id)
    <<hash::binary-size(hash_size), rest::bitstring>> = rest

    {ledger_ops, rest} = LedgerOperations.deserialize(rest)
    <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>> = rest

    {
      %__MODULE__{
        proof_of_work: <<curve_id::8>> <> key,
        proof_of_integrity: <<hash_id::8>> <> hash,
        ledger_operations: ledger_ops,
        signature: signature
      },
      rest
    }
  end
end
