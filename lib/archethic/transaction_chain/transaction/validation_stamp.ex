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
  """
  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          signature: nil | binary(),
          proof_of_work: Crypto.key(),
          proof_of_integrity: Crypto.versioned_hash(),
          proof_of_election: binary(),
          ledger_operations: LedgerOperations.t(),
          recipients: list(Crypto.versioned_hash()),
          error: error() | nil,
          protocol_version: non_neg_integer()
        }

  @spec sign(__MODULE__.t()) :: __MODULE__.t()
  def sign(stamp = %__MODULE__{}) do
    raw_stamp =
      stamp
      |> extract_for_signature()
      |> serialize()

    sig = Crypto.sign_with_last_node_key(raw_stamp)

    %{stamp | signature: sig}
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
        protocol_version: version
      }) do
    %__MODULE__{
      timestamp: timestamp,
      proof_of_work: pow,
      proof_of_integrity: poi,
      proof_of_election: poe,
      ledger_operations: ops,
      recipients: recipients,
      error: error,
      protocol_version: version
    }
  end

  @doc """
  Serialize a validation stamp info binary format

  ## Examples

      iex> %ValidationStamp{
      ...>   timestamp: ~U[2021-05-07 13:11:19Z],
      ...>   proof_of_work: <<0, 0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
      ...>     155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206>>,
      ...>   proof_of_integrity: <<0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
      ...>     28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170>>,
      ...>   proof_of_election: <<195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175, 145, 9, 255, 133, 67,
      ...>     240, 175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82, 6, 218, 31, 220, 114,
      ...>     65, 3, 151, 209, 9, 84, 209, 105, 191, 180, 156, 157, 95, 25, 202, 2, 169,
      ...>     112, 109, 54, 99, 40, 47, 96, 93, 33, 82, 40, 100, 13>>,
      ...>   ledger_operations: %LedgerOperations{
      ...>      fee: 10_000_000,
      ...>      transaction_movements: [],
      ...>      unspent_outputs: []
      ...>   },
      ...>   signature: <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
      ...>     126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
      ...>     238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
      ...>     66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>,
      ...>   protocol_version: current_protocol_version()
      ...> }
      ...> |> ValidationStamp.serialize()
      <<
      # Version
      current_protocol_version()::32,
      # Timestamp
      0, 0, 1, 121, 70, 244, 48, 216,
      # Proof of work
      0, 0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
      155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,
      # Proof of integrity
      0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
      28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170,
      # Proof of election
      195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175, 145, 9, 255, 133, 67,
      240, 175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82, 6, 218, 31, 220, 114,
      65, 3, 151, 209, 9, 84, 209, 105, 191, 180, 156, 157, 95, 25, 202, 2, 169,
      112, 109, 54, 99, 40, 47, 96, 93, 33, 82, 40, 100, 13,
      # Fee
      0, 0, 0, 0, 0, 152, 150, 128,
      # Nb of transaction movements
      1, 0,
      # Nb of unspent outputs
      1, 0,
      # Nb of resolved recipients addresses
      1, 0,
      # No error reported
      0,
      # Signature size
      64,
      # Signature
      67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
      126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
      238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
      66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172
      >>
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ledger_operations,
        recipients: recipients,
        error: error,
        signature: nil,
        protocol_version: version
      }) do
    pow =
      if pow == "" do
        # Empty public key if the no public key matching the origin signature
        <<0::8, 0::8, 0::256>>
      else
        pow
      end

    encoded_recipients_len = length(recipients) |> VarInt.from_value()

    <<version::32, DateTime.to_unix(timestamp, :millisecond)::64, pow::binary, poi::binary,
      poe::binary, LedgerOperations.serialize(ledger_operations, version)::binary,
      encoded_recipients_len::binary, :erlang.list_to_binary(recipients)::binary,
      serialize_error(error)::8>>
  end

  def serialize(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ledger_operations,
        recipients: recipients,
        error: error,
        signature: signature,
        protocol_version: version
      }) do
    pow =
      if pow == "" do
        # Empty public key if the no public key matching the origin signature
        <<0::8, 0::8, 0::256>>
      else
        pow
      end

    encoded_recipients_len = length(recipients) |> VarInt.from_value()

    <<version::32, DateTime.to_unix(timestamp, :millisecond)::64, pow::binary, poi::binary,
      poe::binary, LedgerOperations.serialize(ledger_operations, version)::binary,
      encoded_recipients_len::binary, :erlang.list_to_binary(recipients)::binary,
      serialize_error(error)::8, byte_size(signature)::8, signature::binary>>
  end

  @doc """
  Deserialize an encoded validation stamp

  ## Examples

      iex> <<current_protocol_version()::32, 0, 0, 1, 121, 70, 244, 48, 216, 0, 0, 34, 248, 200, 166, 69, 102, 246, 46, 84,
      ...> 7, 6, 84, 66, 27, 8, 78, 103, 37, 155, 114, 208, 205, 40, 44, 6, 159, 178, 5,
      ...> 186, 168, 237, 206, 0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140,
      ...> 254, 103, 186, 138, 175, 28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180,
      ...> 242, 16, 74, 87, 170, 195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175,
      ...> 145, 9, 255, 133, 67, 240, 175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82,
      ...> 6, 218, 31, 220, 114, 65, 3, 151, 209, 9, 84, 209, 105, 191, 180, 156, 157,
      ...> 95, 25, 202, 2, 169, 112, 109, 54, 99, 40, 47, 96, 93, 33, 82, 40, 100, 13, 0,
      ...> 0, 0, 0, 0, 152, 150, 128, 1, 0, 1, 0, 1, 0, 0, 64, 67, 12, 4, 246, 155, 34,
      ...> 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217, 126, 181, 204, 195, 215,
      ...> 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65, 238, 221, 14, 89, 120, 225,
      ...> 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239, 66, 182, 168, 35, 129, 240,
      ...> 35, 183, 47, 69, 154, 37, 172>>
      ...> |> ValidationStamp.deserialize()
      {
        %ValidationStamp{
          timestamp: ~U[2021-05-07 13:11:19.000Z],
          proof_of_work: <<0, 0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
            155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,>>,
          proof_of_integrity: << 0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
            28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170>>,
          proof_of_election: <<195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175, 145, 9, 255, 133, 67,
            240, 175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82, 6, 218, 31, 220, 114,
            65, 3, 151, 209, 9, 84, 209, 105, 191, 180, 156, 157, 95, 25, 202, 2, 169,
            112, 109, 54, 99, 40, 47, 96, 93, 33, 82, 40, 100, 13>>,
          ledger_operations: %ValidationStamp.LedgerOperations{
            fee: 10_000_000,
            transaction_movements: [],
            unspent_outputs: []
          },
          recipients: [],
          error: nil,
          signature: <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
            126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
            238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
            66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>,
          protocol_version: current_protocol_version()
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
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

    {
      %__MODULE__{
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
        error: error
      }) do
    %{
      timestamp: timestamp,
      proof_of_work: pow,
      proof_of_integrity: poi,
      proof_of_election: poe,
      ledger_operations: LedgerOperations.to_map(ledger_operations),
      recipients: recipients,
      signature: signature,
      error: error
    }
  end

  def to_map(nil), do: nil

  @doc """
  Determine if the validation stamp signature is valid
  """
  @spec valid_signature?(__MODULE__.t(), Crypto.key()) :: boolean()
  def valid_signature?(%__MODULE__{signature: nil}, _public_key), do: false

  def valid_signature?(
        stamp = %__MODULE__{signature: signature},
        public_key
      )
      when is_binary(signature) do
    raw_stamp =
      stamp
      |> extract_for_signature
      |> serialize

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

  defp deserialize_error(0), do: nil
  defp deserialize_error(1), do: :invalid_pending_transaction
  defp deserialize_error(2), do: :invalid_inherit_constraints
  defp deserialize_error(3), do: :insufficient_funds
  defp deserialize_error(4), do: :invalid_contract_execution
  defp deserialize_error(5), do: :invalid_recipients_execution
end
