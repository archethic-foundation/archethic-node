defmodule Archethic.TransactionChain.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  alias Archethic.Crypto

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  alias __MODULE__.LedgerOperations

  defstruct [
    :protocol_version,
    :genesis_address,
    :timestamp,
    :signature,
    :proof_of_work,
    :proof_of_integrity,
    :proof_of_election,
    ledger_operations: %LedgerOperations{},
    recipients: [],
    error: nil
  ]

  @type error ::
          :invalid_pending_transaction
          | :invalid_inherit_constraints
          | :insufficient_funds
          | :invalid_contract_execution
          | :invalid_recipients_execution
          | :recipients_not_distinct
          | :invalid_contract_context_inputs

  @typedoc """
  Validation performed by a coordinator:
  - Timestamp: DateTime instance representing the timestamp of the transaction validation
  - Proof of work: Origin public key matching the origin signature
  - Proof of integrity: Integrity proof from the entire transaction chain
  - Proof of election: Digest which define the election's order of validation nodes
  - Ledger Operations: Set of ledger operations taken by the network such as fee, transaction movements and unspent outputs
  - Recipients: List of the last smart contract chain resolved addresses
  - Contract validation: Determine if the transaction coming from a contract is valid according to the constraints
  - Signature: generated from the coordinator private key to avoid non-repudiation of the stamp
  - Error: Error returned by the pending transaction validation or after mining context
  - Protocol version: Version of the protocol
  - Genesis address: Genesis of the chain. Added in protocol_version=9
  """
  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          signature: nil | binary(),
          proof_of_work: Crypto.key(),
          proof_of_integrity: Crypto.versioned_hash(),
          proof_of_election: binary(),
          ledger_operations: LedgerOperations.t(),
          recipients: list(Crypto.prepended_hash()),
          genesis_address: Crypto.prepended_hash(),
          error: error() | nil,
          protocol_version: non_neg_integer()
        }

  @spec sign(__MODULE__.t()) :: __MODULE__.t()
  def sign(stamp = %__MODULE__{protocol_version: protocol_version}) do
    sig =
      stamp
      |> extract_for_signature()
      |> serialize(serialize_genesis?: protocol_version >= 9)
      |> Crypto.sign_with_mining_node_key()

    %__MODULE__{stamp | signature: sig}
  end

  @doc """
  Extract fields to prepare serialization for the signature
  """
  @spec extract_for_signature(__MODULE__.t()) :: __MODULE__.t()
  def extract_for_signature(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ops,
        recipients: recipients,
        error: error,
        protocol_version: version,
        genesis_address: genesis_address
      }) do
    %__MODULE__{
      timestamp: timestamp,
      proof_of_work: pow,
      proof_of_integrity: poi,
      proof_of_election: poe,
      ledger_operations: ops,
      recipients: recipients,
      error: error,
      protocol_version: version,
      genesis_address: genesis_address
    }
  end

  @doc """
  Serialize a validation stamp info binary format

  Opts:
    serialize_genesis?: true | false
  """
  @spec serialize(t()) :: bitstring()
  def serialize(stamp, opts \\ [])

  def serialize(
        %__MODULE__{
          timestamp: timestamp,
          proof_of_work: pow,
          proof_of_integrity: poi,
          proof_of_election: poe,
          ledger_operations: ledger_operations,
          recipients: recipients,
          error: error,
          signature: signature,
          protocol_version: version,
          genesis_address: genesis_address
        },
        opts
      ) do
    pow =
      if pow == "" do
        # Empty public key if the no public key matching the origin signature
        <<0::8, 0::8, 0::256>>
      else
        pow
      end

    encoded_recipients_len = length(recipients) |> VarInt.from_value()

    <<version::32, DateTime.to_unix(timestamp, :millisecond)::64, pow::binary, poi::binary,
      poe::binary, LedgerOperations.serialize(ledger_operations, version)::bitstring,
      encoded_recipients_len::binary, :erlang.list_to_binary(recipients)::binary,
      serialize_error(error)::8>>
    |> maybe_add_signature(signature)
    |> maybe_add_genesis(genesis_address, Keyword.get(opts, :serialize_genesis?, true))
  end

  defp maybe_add_signature(bin, nil), do: bin

  defp maybe_add_signature(bin, signature),
    do: <<bin::bitstring, byte_size(signature)::8, signature::binary>>

  defp maybe_add_genesis(bin, _genesis_address, false), do: bin

  defp maybe_add_genesis(bin, genesis_address, true),
    do: <<bin::bitstring, genesis_address::binary>>

  @doc """
  Deserialize an encoded validation stamp

  Never used after a serialize(serialize_genesis?: false)
  """
  @spec deserialize(bin :: bitstring()) :: {t(), bitstring()}
  def deserialize(<<version::32, timestamp::64, rest::bitstring>>) do
    <<pow_curve_id::8, pow_origin_id::8, rest::bitstring>> = rest
    pow_key_size = Crypto.key_size(pow_curve_id)
    <<pow_key::binary-size(pow_key_size), rest::bitstring>> = rest
    pow = <<pow_curve_id::8, pow_origin_id::8, pow_key::binary>>

    <<poi_hash_id::8, rest::bitstring>> = rest
    poi_hash_size = Crypto.hash_size(poi_hash_id)
    <<poi_hash::binary-size(poi_hash_size), poe::binary-size(64), rest::bitstring>> = rest

    {ledger_ops, <<rest::bitstring>>} = LedgerOperations.deserialize(rest, version)

    {recipients_length, rest} = rest |> VarInt.get_value()

    {recipients, <<error_byte::8, rest::bitstring>>} =
      Utils.deserialize_addresses(rest, recipients_length, [])

    error = deserialize_error(error_byte)

    <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>> = rest

    {genesis_address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{
        genesis_address: genesis_address,
        timestamp: DateTime.from_unix!(timestamp, :millisecond),
        proof_of_work: pow,
        proof_of_integrity: <<poi_hash_id::8, poi_hash::binary>>,
        proof_of_election: poe,
        ledger_operations: ledger_ops,
        recipients: recipients,
        error: error,
        signature: signature,
        protocol_version: version
      },
      rest
    }
  end

  @spec cast(map()) :: __MODULE__.t()
  def cast(stamp = %{}) do
    %__MODULE__{
      timestamp: Map.get(stamp, :timestamp),
      proof_of_work: Map.get(stamp, :proof_of_work),
      proof_of_integrity: Map.get(stamp, :proof_of_integrity),
      proof_of_election: Map.get(stamp, :proof_of_election),
      ledger_operations:
        Map.get(stamp, :ledger_operations, %LedgerOperations{}) |> LedgerOperations.cast(),
      recipients: Map.get(stamp, :recipients, []),
      signature: Map.get(stamp, :signature),
      error: Map.get(stamp, :error),
      genesis_address: Map.get(stamp, :genesis_address),
      protocol_version: Map.get(stamp, :protocol_version)
    }
  end

  def cast(nil), do: nil

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ledger_operations,
        recipients: recipients,
        signature: signature,
        error: error,
        genesis_address: genesis_address,
        protocol_version: protocol_version
      }) do
    %{
      timestamp: timestamp,
      proof_of_work: pow,
      proof_of_integrity: poi,
      proof_of_election: poe,
      ledger_operations: LedgerOperations.to_map(ledger_operations, protocol_version),
      recipients: recipients,
      signature: signature,
      error: error,
      genesis_address: genesis_address
    }
  end

  def to_map(nil), do: nil

  @doc """
  Determine if the validation stamp signature is valid
  """
  @spec valid_signature?(__MODULE__.t(), Crypto.key()) :: boolean()
  def valid_signature?(%__MODULE__{signature: nil}, _public_key), do: false

  def valid_signature?(
        stamp = %__MODULE__{signature: signature, protocol_version: protocol_version},
        public_key
      )
      when is_binary(signature) do
    raw_stamp =
      stamp
      |> extract_for_signature()
      |> serialize(serialize_genesis?: protocol_version >= 9)

    Crypto.verify?(signature, raw_stamp, public_key)
  end

  @doc """
  Generates a dummy ValidationStamp.
  This should only be used in very specific cases
  """
  @spec generate_dummy(Keyword.t()) :: t()
  def generate_dummy(opts \\ []) do
    %__MODULE__{
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      genesis_address:
        Keyword.get(opts, :genesis_address, <<0::16, :crypto.strong_rand_bytes(32)::binary>>),
      protocol_version: 1,
      proof_of_work: :crypto.strong_rand_bytes(32),
      proof_of_election: :crypto.strong_rand_bytes(32),
      proof_of_integrity: :crypto.strong_rand_bytes(32)
    }
  end

  defp serialize_error(nil), do: 0
  defp serialize_error(:invalid_pending_transaction), do: 1
  defp serialize_error(:invalid_inherit_constraints), do: 2
  defp serialize_error(:insufficient_funds), do: 3
  defp serialize_error(:invalid_contract_execution), do: 4
  defp serialize_error(:invalid_recipients_execution), do: 5
  defp serialize_error(:recipients_not_distinct), do: 6
  defp serialize_error(:invalid_contract_context_inputs), do: 7

  defp deserialize_error(0), do: nil
  defp deserialize_error(1), do: :invalid_pending_transaction
  defp deserialize_error(2), do: :invalid_inherit_constraints
  defp deserialize_error(3), do: :insufficient_funds
  defp deserialize_error(4), do: :invalid_contract_execution
  defp deserialize_error(5), do: :invalid_recipients_execution
  defp deserialize_error(6), do: :recipients_not_distinct
  defp deserialize_error(7), do: :invalid_contract_context_inputs
end
