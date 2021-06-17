defmodule Uniris.TransactionChain.Transaction.ValidationStamp do
  @moduledoc """
  Represents a validation stamp created by a coordinator on a pending transaction
  """

  alias Uniris.Crypto

  alias __MODULE__.LedgerOperations

  defstruct [
    :timestamp,
    :signature,
    :proof_of_work,
    :proof_of_integrity,
    :proof_of_election,
    ledger_operations: %LedgerOperations{},
    recipients: [],
    errors: []
  ]

  @type error :: :contract_validation | :oracle_validation

  @typedoc """
  Validation performed by a coordinator:
  - Timestamp: DateTime instance representing the timestamp of the transaction validation
  - Proof of work: Origin public key matching the origin signature
  - Proof of integrity: Integrity proof from the entire transaction chain
  - Proof of election: Digest which define the election's order of validation nodes
  - Ledger Operations: Set of ledger operations taken by the network such as fee, node movements, transaction movements and unspent outputs
  - Recipients: List of the last smart contract chain resolved addresses
  - Contract validation: Determine if the transaction coming from a contract is valid according to the constraints
  - Signature: generated from the coordinator private key to avoid non-repudiation of the stamp
  - Errors: list of errors returned by the pending transaction validation or after mining context
  """
  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          signature: nil | binary(),
          proof_of_work: Crypto.key(),
          proof_of_integrity: Crypto.versioned_hash(),
          proof_of_election: binary(),
          ledger_operations: LedgerOperations.t(),
          recipients: list(Crypto.versioned_hash()),
          errors: list(atom())
        }

  @spec sign(__MODULE__.t()) :: __MODULE__.t()
  def sign(stamp = %__MODULE__{}) do
    sig =
      stamp
      |> extract_for_signature()
      |> serialize()
      |> Crypto.sign_with_last_node_key()

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
        errors: errors
      }) do
    %__MODULE__{
      timestamp: timestamp,
      proof_of_work: pow,
      proof_of_integrity: poi,
      proof_of_election: poe,
      ledger_operations: ops,
      recipients: recipients,
      errors: errors
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
      ...>      fee: 0.1,
      ...>      transaction_movements: [],
      ...>      node_movements: [],
      ...>      unspent_outputs: []
      ...>   },
      ...>   signature: <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
      ...>     126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
      ...>     238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
      ...>     66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>
      ...> }
      ...> |> ValidationStamp.serialize()
      <<
      # Timestamp
      96, 149, 60, 119,
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
      63, 185, 153, 153, 153, 153, 153, 154,
      # Nb of transaction movements
      0,
      # Nb of node movements
      0,
      # Nb of unspent outputs
      0,
      # Nb of resolved recipients addresses
      0,
      # Nb errors reported
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
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ledger_operations,
        recipients: recipients,
        errors: errors,
        signature: nil
      }) do
    pow =
      if pow == "" do
        # Empty public key if the no public key matching the origin signature
        <<0::8, 0::8, 0::256>>
      else
        pow
      end

    <<DateTime.to_unix(timestamp)::32, pow::binary, poi::binary, poe::binary,
      LedgerOperations.serialize(ledger_operations)::binary, length(recipients)::8,
      :erlang.list_to_binary(recipients)::binary, length(errors)::8,
      serialize_errors(errors)::bitstring>>
  end

  def serialize(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ledger_operations,
        recipients: recipients,
        errors: errors,
        signature: signature
      }) do
    pow =
      if pow == "" do
        # Empty public key if the no public key matching the origin signature
        <<0::8, 0::8, 0::256>>
      else
        pow
      end

    <<DateTime.to_unix(timestamp)::32, pow::binary, poi::binary, poe::binary,
      LedgerOperations.serialize(ledger_operations)::binary, length(recipients)::8,
      :erlang.list_to_binary(recipients)::binary, length(errors)::8,
      serialize_errors(errors)::bitstring, byte_size(signature)::8, signature::binary>>
  end

  @doc """
  Deserialize an encoded validation stamp

  ## Examples

      iex> <<96, 149, 60, 119, 0, 0,  34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
      ...> 155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,
      ...> 0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
      ...> 28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170,
      ...> 195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175, 145, 9, 255, 133, 67,
      ...> 240, 175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82, 6, 218, 31, 220, 114,
      ...> 65, 3, 151, 209, 9, 84, 209, 105, 191, 180, 156, 157, 95, 25, 202, 2, 169,
      ...> 112, 109, 54, 99, 40, 47, 96, 93, 33, 82, 40, 100, 13,
      ...> 63, 185, 153, 153, 153, 153, 153, 154, 0, 0, 0, 0, 0, 64,
      ...> 67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
      ...> 126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
      ...> 238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
      ...> 66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>
      ...> |> ValidationStamp.deserialize()
      {
        %ValidationStamp{
          timestamp: ~U[2021-05-07 13:11:19Z],
          proof_of_work: <<0, 0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37,
            155, 114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206,>>,
          proof_of_integrity: << 0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175,
            28, 156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170>>,
          proof_of_election: <<195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175, 145, 9, 255, 133, 67,
            240, 175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82, 6, 218, 31, 220, 114,
            65, 3, 151, 209, 9, 84, 209, 105, 191, 180, 156, 157, 95, 25, 202, 2, 169,
            112, 109, 54, 99, 40, 47, 96, 93, 33, 82, 40, 100, 13>>,
          ledger_operations: %ValidationStamp.LedgerOperations{
            fee: 0.1,
            transaction_movements: [],
            node_movements: [],
            unspent_outputs: []
          },
          recipients: [],
          errors: [],
          signature: <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217,
            126, 181, 204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65,
            238, 221, 14, 89, 120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239,
            66, 182, 168, 35, 129, 240, 35, 183, 47, 69, 154, 37, 172>>
        },
        ""
      }
  """
  def deserialize(<<timestamp::32, rest::bitstring>>) do
    <<pow_curve_id::8, pow_origin_id::8, rest::bitstring>> = rest
    pow_key_size = Crypto.key_size(pow_curve_id)
    <<pow_key::binary-size(pow_key_size), rest::bitstring>> = rest
    pow = <<pow_curve_id::8, pow_origin_id::8, pow_key::binary>>

    <<poi_hash_id::8, rest::bitstring>> = rest
    poi_hash_size = Crypto.hash_size(poi_hash_id)
    <<poi_hash::binary-size(poi_hash_size), poe::binary-size(64), rest::bitstring>> = rest

    {ledger_ops, <<recipients_length::8, rest::bitstring>>} = LedgerOperations.deserialize(rest)

    {recipients, <<nb_errors::8, rest::bitstring>>} =
      deserialize_list_of_recipients_addresses(rest, recipients_length, [])

    {errors, rest} = deserialize_errors(rest, nb_errors)

    <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>> = rest

    {
      %__MODULE__{
        timestamp: DateTime.from_unix!(timestamp),
        proof_of_work: pow,
        proof_of_integrity: <<poi_hash_id::8, poi_hash::binary>>,
        proof_of_election: poe,
        ledger_operations: ledger_ops,
        recipients: recipients,
        errors: errors,
        signature: signature
      },
      rest
    }
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(stamp = %{}) do
    %__MODULE__{
      timestamp: Map.get(stamp, :timestamp),
      proof_of_work: Map.get(stamp, :proof_of_work),
      proof_of_integrity: Map.get(stamp, :proof_of_integrity),
      proof_of_election: Map.get(stamp, :proof_of_election),
      ledger_operations:
        Map.get(stamp, :ledger_operations, %LedgerOperations{}) |> LedgerOperations.from_map(),
      recipients: Map.get(stamp, :recipients, []),
      signature: Map.get(stamp, :signature),
      errors: Map.get(stamp, :errors)
    }
  end

  def from_map(nil), do: nil

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{
        timestamp: timestamp,
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: ledger_operations,
        recipients: recipients,
        signature: signature,
        errors: errors
      }) do
    %{
      timestamp: timestamp,
      proof_of_work: pow,
      proof_of_integrity: poi,
      proof_of_election: poe,
      ledger_operations: LedgerOperations.to_map(ledger_operations),
      recipients: recipients,
      signature: signature,
      errors: errors
    }
  end

  def to_map(nil), do: nil

  @doc """
  Determine if the validation stamp signature is valid
  """
  @spec valid_signature?(__MODULE__.t(), Crypto.key()) :: boolean()
  def valid_signature?(%__MODULE__{signature: nil}, _public_key), do: false

  def valid_signature?(stamp = %__MODULE__{signature: signature}, public_key)
      when is_binary(signature) do
    raw_stamp =
      stamp
      |> extract_for_signature
      |> serialize

    Crypto.verify?(signature, raw_stamp, public_key)
  end

  defp deserialize_list_of_recipients_addresses(rest, 0, _acc), do: {[], rest}

  defp deserialize_list_of_recipients_addresses(rest, nb_recipients, acc)
       when length(acc) == nb_recipients do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_list_of_recipients_addresses(
         <<hash_id::8, rest::bitstring>>,
         nb_recipients,
         acc
       ) do
    hash_size = Crypto.hash_size(hash_id)
    <<hash::binary-size(hash_size), rest::bitstring>> = rest

    deserialize_list_of_recipients_addresses(rest, nb_recipients, [
      <<hash_id::8, hash::binary>> | acc
    ])
  end

  defp serialize_errors(errors, acc \\ [])
  defp serialize_errors([], acc), do: :erlang.list_to_bitstring(acc)

  defp serialize_errors([error | rest], acc) do
    serialize_errors(rest, [serialize_error(error) | acc])
  end

  defp deserialize_errors(bitstring, nb_errors, acc \\ [])

  defp deserialize_errors(rest, nb_errors, acc) when length(acc) == nb_errors do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_errors(<<error::8, rest::bitstring>>, nb_errors, acc) do
    deserialize_errors(rest, nb_errors, [deserialize_error(error) | acc])
  end

  defp serialize_error(:pending_transaction), do: 0
  defp serialize_error(:contract_validation), do: 1
  defp serialize_error(:oracle_validation), do: 2

  defp deserialize_error(0), do: :pending_transaction
  defp deserialize_error(1), do: :contract_validation
  defp deserialize_error(2), do: :oracle_validation
end
