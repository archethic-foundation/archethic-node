defmodule UnirisCore.Transaction do
  @moduledoc """
  Represents the main unit of the Uniris network and its Transaction Chain.

  Blocks are reduce to its unitary form to provide high scalability, avoiding double spending attack and chain integrity
  """
  alias __MODULE__.ValidationStamp
  alias __MODULE__.CrossValidationStamp
  alias UnirisCore.TransactionData
  alias UnirisCore.Crypto

  defstruct [
    :address,
    :type,
    :timestamp,
    :data,
    :previous_public_key,
    :previous_signature,
    :origin_signature,
    :validation_stamp,
    :cross_validation_stamps
  ]

  @typedoc """
  Represent a transaction in pending validation
  - Address: hash of the new generated public key for the given transaction
  - Type: transaction type
  - Timestamp: creation date of the transaction
  - Data: transaction data zone (identity, keychain, smart contract, etc.)
  - Previous signature: signature from the previous public key
  - Previous public key: previous generated public key matching the previous signature
  - Origin signature: signature from the device which originated the transaction (used in the Proof of work)

  When the transaction is validated the following fields are filled:
  - Validation stamp: coordinator work result
  - Cross validation stamps: endorsements of the validation stamp from the coordinator
  """
  @type t() :: %__MODULE__{
          address: binary(),
          type: transaction_type(),
          timestamp: DateTime.t(),
          data: Data.t(),
          previous_public_key: Crypto.key(),
          previous_signature: binary(),
          origin_signature: binary(),
          validation_stamp: nil | ValidationStamp.t(),
          cross_validation_stamps: nil | list(CrossValidationStamp.t())
        }

  @typedoc """
  Supported transaction types
  """
  @type transaction_type ::
          :identity
          | :keychain
          | :transfer
          | :node
          | :node_shared_secrets
          | :origin_shared_secrets
          | :code
          | :beacon
          | :hosting

  @transaction_types [
    :identity,
    :keychain,
    :transfer,
    :node,
    :node_shared_secrets,
    :origin_shared_secrets,
    :code,
    :beacon,
    :hosting
  ]

  @doc """
  Create a new pending transaction using the Crypto keystore to find out
  the seed and the transaction index
  """
  @spec new(type :: __MODULE__.transaction_type(), data :: TransactionData.t()) :: __MODULE__.t()
  def new(type, data = %TransactionData{}) when type in [:node, :node_shared_secrets, :beacon] do
    {previous_public_key, next_public_key} = get_transaction_public_keys(type)

    %__MODULE__{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: DateTime.utc_now(),
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction()
    |> origin_sign_transaction()
  end

  @doc """
  Create a new pending transaction
  """
  @spec new(
          type :: __MODULE__.transaction_type(),
          data :: TransactionData.t(),
          seed :: binary(),
          index :: non_neg_integer()
        ) :: __MODULE__.t()
  def new(type, data = %TransactionData{}, seed, index)
      when type in @transaction_types and is_binary(seed) and is_integer(index) and index >= 0 do
    {previous_public_key, previous_private_key} = Crypto.derivate_keypair(seed, index)
    {next_public_key, _} = Crypto.derivate_keypair(seed, index + 1)

    %__MODULE__{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: DateTime.utc_now(),
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction(previous_private_key)
    |> origin_sign_transaction()
  end

  defp get_transaction_public_keys(:node) do
    key_index = Crypto.number_of_node_keys()
    previous_public_key = Crypto.node_public_key(key_index)
    next_public_key = Crypto.node_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  # TODO: use the sync seed in the node shared secrets
  defp get_transaction_public_keys(:beacon) do
    key_index = Crypto.number_of_node_keys()
    previous_public_key = Crypto.node_public_key(key_index)
    next_public_key = Crypto.node_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  defp get_transaction_public_keys(:node_shared_secrets) do
    key_index = Crypto.number_of_node_shared_secrets_keys()
    previous_public_key = Crypto.node_shared_secrets_public_key(key_index)
    next_public_key = Crypto.node_shared_secrets_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  defp previous_sign_transaction(tx = %__MODULE__{type: :node}) do
    key_index = Crypto.number_of_node_keys()

    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign_with_node_key(key_index)

    %{tx | previous_signature: previous_signature}
  end

  # TODO: use the sync seed in the node shared secrets
  defp previous_sign_transaction(tx = %__MODULE__{type: :beacon}) do
    key_index = Crypto.number_of_node_keys()

    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign_with_node_key(key_index)

    %{tx | previous_signature: previous_signature}
  end

  defp previous_sign_transaction(tx = %__MODULE__{type: :node_shared_secrets}) do
    key_index = Crypto.number_of_node_shared_secrets_keys()

    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign_with_node_shared_secrets_key(key_index)

    %{tx | previous_signature: previous_signature}
  end

  defp previous_sign_transaction(tx = %__MODULE__{}, private_key) do
    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign(private_key)

    %{tx | previous_signature: previous_signature}
  end

  defp origin_sign_transaction(tx) do
    origin_sig =
      tx
      |> extract_for_origin_signature
      |> serialize()
      |> Crypto.sign_with_node_key(0)

    %{tx | origin_signature: origin_sig}
  end

  @doc """
  Extract the transaction payload for the previous signature including address, timestamp, type and data
  """
  @spec extract_for_previous_signature(__MODULE__.t()) :: __MODULE__.t()
  def extract_for_previous_signature(tx = %__MODULE__{}) do
    %__MODULE__{
      address: tx.address,
      timestamp: tx.timestamp,
      type: tx.type,
      data: tx.data
    }
  end

  @doc """
  Extract the transaction payload for the origin signature including address, timestamp,
  type data, previous_public_key and previous_signature
  """
  @spec extract_for_origin_signature(__MODULE__.t()) :: __MODULE__.t()
  def extract_for_origin_signature(tx = %__MODULE__{}) do
    %__MODULE__{
      address: tx.address,
      timestamp: tx.timestamp,
      type: tx.type,
      data: tx.data,
      previous_public_key: tx.previous_public_key,
      previous_signature: tx.previous_signature
    }
  end

  @doc """
  Determines if a pending transaction is valid
  """
  @spec valid_pending_transaction?(__MODULE__.t()) :: boolean()
  def valid_pending_transaction?(tx = %__MODULE__{}) do
    raw_tx =
      tx
      |> extract_for_previous_signature()
      |> serialize()

    cond do
      tx.type not in @transaction_types ->
        false

      !Crypto.verify(tx.previous_signature, raw_tx, tx.previous_public_key) ->
        false

      true ->
        # TODO: perform additional checks regarding the data block
        true
    end
  end

  @doc """
  Serialize transaction type
  """
  @spec serialize_type(transaction_type()) :: non_neg_integer()
  def serialize_type(:identity), do: 0
  def serialize_type(:keychain), do: 1
  def serialize_type(:transfer), do: 2
  def serialize_type(:node), do: 3
  def serialize_type(:node_shared_secrets), do: 4
  def serialize_type(:origin_shared_secrets), do: 5
  def serialize_type(:code), do: 6
  def serialize_type(:beacon), do: 7
  def serialize_type(:hosting), do: 8

  @doc """
  Parse a serialize transaction type
  """
  @spec parse_type(non_neg_integer()) :: transaction_type()
  def parse_type(0), do: :identity
  def parse_type(1), do: :keychain
  def parse_type(2), do: :transfer
  def parse_type(3), do: :node
  def parse_type(4), do: :node_shared_secrets
  def parse_type(5), do: :origin_shared_secrets
  def parse_type(6), do: :code
  def parse_type(7), do: :beacon
  def parse_type(8), do: :hosting

  @doc """
  Determines if a transaction type is a network one
  """
  @spec network_type?(transaction_type()) :: boolean()
  def network_type?(:node), do: true
  def network_type?(:node_shared_secrets), do: true
  def network_type?(:origin_shared_secrets), do: true
  def network_type?(:code), do: true
  def network_type?(_), do: false

  @doc """
  Extract the pending transaction fields from a transaction
  """
  @spec to_pending(__MODULE__.t()) :: __MODULE__.t()
  def to_pending(tx = %__MODULE__{}) do
    %{tx | validation_stamp: nil, cross_validation_stamps: nil}
  end

  @doc """
  Check if the cross validation stamps are valid
  """
  @spec valid_cross_validation_stamps?(__MODULE__.t()) :: boolean
  def valid_cross_validation_stamps?(%__MODULE__{
        validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
      }) do
    Enum.all?(cross_validation_stamps, &CrossValidationStamp.valid?(&1, validation_stamp))
  end

  @doc """
  Determines if the atomic commitment is reached for the cross validate stamps
  """
  @spec atomic_commitment?(__MODULE__.t()) :: boolean()
  def atomic_commitment?(%__MODULE__{cross_validation_stamps: cross_validation_stamps}) do
    case Enum.dedup_by(cross_validation_stamps, & &1.inconsistencies) do
      [_ | []] ->
        true

      [_ | _] ->
        false
    end
  end

  @doc """
  Serialize a transaction into binary format

  ## Examples

      iex> UnirisCore.Transaction.serialize(%UnirisCore.Transaction{
      ...>   address: <<0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
      ...>     196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85>>,
      ...>   type: :transfer,
      ...>   timestamp: ~U[2020-06-24 12:56:33Z],
      ...>   data: %UnirisCore.TransactionData{},
      ...>   previous_public_key: <<0, 61, 250, 128, 151, 100, 231, 128, 158, 139, 88, 128, 68, 236, 240, 238, 116,
      ...>     186, 164, 87, 3, 60, 198, 21, 248, 64, 207, 58, 221, 192, 131, 180, 213>>,
      ...>   previous_signature: <<65, 66, 248, 246, 119, 69, 36, 103, 249, 201, 252, 154, 69, 24, 48, 18, 63,
      ...>    65, 5, 10, 248, 37, 245, 101, 19, 118, 235, 82, 161, 165, 62, 43, 249, 237,
      ...>    223, 226, 253, 241, 155, 33, 45, 164, 50, 14, 176, 241, 3, 107, 12, 177, 47,
      ...>    20, 235, 147, 252, 28, 136, 226, 176, 180, 170, 85, 3, 151>>,
      ...>   origin_signature: <<10, 165, 166, 170, 175, 231, 164, 69, 83, 150, 36, 135, 144, 20, 104, 226,
      ...>    183, 149, 250, 90, 117, 107, 162, 17, 63, 118, 229, 125, 15, 189, 245, 64,
      ...>    214, 93, 126, 179, 251, 41, 101, 249, 226, 180, 88, 241, 184, 154, 181, 156,
      ...>    178, 213, 132, 220, 31, 63, 23, 165, 174, 82, 182, 120, 142, 87, 34, 132>>,
      ...>   validation_stamp: %UnirisCore.Transaction.ValidationStamp{
      ...>      proof_of_work: <<0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
      ...>        186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99>>,
      ...>      proof_of_integrity: <<0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
      ...>        133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17>>,
      ...>      ledger_operations: %UnirisCore.Transaction.ValidationStamp.LedgerOperations{
      ...>         fee: 0.1,
      ...>         transaction_movements: [],
      ...>         node_movements: [],
      ...>         unspent_outputs: []
      ...>      },
      ...>      signature: <<47, 48, 215, 147, 153, 120, 199, 102, 130, 0, 51, 138, 164, 146, 99, 2, 74,
      ...>       116, 89, 117, 185, 72, 109, 10, 198, 124, 44, 66, 126, 43, 85, 186, 105, 169,
      ...>       159, 56, 129, 179, 207, 176, 97, 190, 162, 240, 186, 164, 58, 41, 221, 27,
      ...>       234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251>>
      ...>   },
      ...>   cross_validation_stamps: [
      ...>     %UnirisCore.Transaction.CrossValidationStamp{
      ...>          node_public_key: <<0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
      ...>            115, 26, 63, 191, 152, 219, 245, 217, 29, 140, 42, 58, 104, 109, 108>>,
      ...>          signature: <<171, 239, 218, 149, 194, 162, 14, 64, 73, 160, 142, 149, 100, 135, 215, 48,
      ...>            133, 74, 61, 203, 113, 16, 163, 135, 41, 8, 227, 82, 131, 248, 200, 50, 113,
      ...>            195, 241, 169, 208, 28, 2, 53, 49, 141, 89, 99, 12, 189, 115, 188, 75, 11, 42,
      ...>            149, 223, 53, 234, 144, 115, 42, 99, 54, 94, 120, 25, 193>>,
      ...>          inconsistencies: []
      ...>     }
      ...>   ]
      ...> })
      <<
      # Address
      0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
      196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85,
      # Transaction type,
      2,
      # Timestamp
      94, 243, 77, 129,
      # Code size
      0, 0, 0, 0,
      # Content size
      0, 0, 0, 0,
      # Secret size
      0, 0, 0, 0,
      # Nb authorized keys
      0,
      # Nb transfers
      0,
      # Nb recipients
      0,
      # Previous public key
      0, 61, 250, 128, 151, 100, 231, 128, 158, 139, 88, 128, 68, 236, 240, 238, 116,
      186, 164, 87, 3, 60, 198, 21, 248, 64, 207, 58, 221, 192, 131, 180, 213,
      # Previous signature size
      64,
      # Previous signature
      65, 66, 248, 246, 119, 69, 36, 103, 249, 201, 252, 154, 69, 24, 48, 18, 63,
      65, 5, 10, 248, 37, 245, 101, 19, 118, 235, 82, 161, 165, 62, 43, 249, 237,
      223, 226, 253, 241, 155, 33, 45, 164, 50, 14, 176, 241, 3, 107, 12, 177, 47,
      20, 235, 147, 252, 28, 136, 226, 176, 180, 170, 85, 3, 151,
      # Origin signature size
      64,
      # Origin signature
      10, 165, 166, 170, 175, 231, 164, 69, 83, 150, 36, 135, 144, 20, 104, 226,
      183, 149, 250, 90, 117, 107, 162, 17, 63, 118, 229, 125, 15, 189, 245, 64,
      214, 93, 126, 179, 251, 41, 101, 249, 226, 180, 88, 241, 184, 154, 181, 156,
      178, 213, 132, 220, 31, 63, 23, 165, 174, 82, 182, 120, 142, 87, 34, 132,
      # Validated transaction
      1,
      # Proof of work
      0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
      186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99,
      # Proof of integrity
      0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
      133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17,
      # Fee
      63, 185, 153, 153, 153, 153, 153, 154,
      # Nb transaction movements
      0,
      # Nb node movements
      0,
      # Nb unspent outputs,
      0,
      # Signature size
      64,
      # Signature
      47, 48, 215, 147, 153, 120, 199, 102, 130, 0, 51, 138, 164, 146, 99, 2, 74,
      116, 89, 117, 185, 72, 109, 10, 198, 124, 44, 66, 126, 43, 85, 186, 105, 169,
      159, 56, 129, 179, 207, 176, 97, 190, 162, 240, 186, 164, 58, 41, 221, 27,
      234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251,
      # Nb cross validation stamps
      1,
      # Node public key
      0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
      115, 26, 63, 191, 152, 219, 245, 217, 29, 140, 42, 58, 104, 109, 108,
      # Signature size
      64,
      # Signature
      171, 239, 218, 149, 194, 162, 14, 64, 73, 160, 142, 149, 100, 135, 215, 48,
      133, 74, 61, 203, 113, 16, 163, 135, 41, 8, 227, 82, 131, 248, 200, 50, 113,
      195, 241, 169, 208, 28, 2, 53, 49, 141, 89, 99, 12, 189, 115, 188, 75, 11, 42,
      149, 223, 53, 234, 144, 115, 42, 99, 54, 94, 120, 25, 193,
      # Nb inconsitencies
      0
      >>
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        data: data,
        previous_public_key: nil,
        previous_signature: nil,
        origin_signature: nil,
        validation_stamp: nil,
        cross_validation_stamps: nil
      }) do
    <<address::binary, serialize_type(type)::8, DateTime.to_unix(timestamp)::32,
      TransactionData.serialize(data)::binary>>
  end

  def serialize(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        data: data,
        previous_public_key: previous_public_key,
        previous_signature: previous_signature,
        origin_signature: nil,
        validation_stamp: nil,
        cross_validation_stamps: nil
      }) do
    <<address::binary, serialize_type(type)::8, DateTime.to_unix(timestamp)::32,
      TransactionData.serialize(data)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary>>
  end

  def serialize(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        data: data,
        previous_public_key: previous_public_key,
        previous_signature: previous_signature,
        origin_signature: origin_signature,
        validation_stamp: nil,
        cross_validation_stamps: nil
      }) do
    <<address::binary, serialize_type(type)::8, DateTime.to_unix(timestamp)::32,
      TransactionData.serialize(data)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary,
      byte_size(origin_signature)::8, origin_signature::binary, 0::8>>
  end

  def serialize(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        data: data,
        previous_public_key: previous_public_key,
        previous_signature: previous_signature,
        origin_signature: origin_signature,
        validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
      }) do
    cross_validation_stamps_bin =
      cross_validation_stamps
      |> Enum.map(&CrossValidationStamp.serialize/1)
      |> :erlang.list_to_binary()

    <<address::binary, serialize_type(type)::8, DateTime.to_unix(timestamp)::32,
      TransactionData.serialize(data)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary,
      byte_size(origin_signature)::8, origin_signature::binary, 1::8,
      ValidationStamp.serialize(validation_stamp)::binary, length(cross_validation_stamps)::8,
      cross_validation_stamps_bin::binary>>
  end

  @doc """
  Deserialize an encoded transaction

  ## Examples

      iex> <<0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
      ...> 196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85, 2, 94, 243, 77, 129,
      ...> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 61, 250, 128, 151, 100, 231, 128, 158, 139,
      ...> 88, 128, 68, 236, 240, 238, 116, 186, 164, 87, 3, 60, 198, 21, 248, 64, 207, 58, 221, 192,
      ...> 131, 180, 213, 64, 65, 66, 248, 246, 119, 69, 36, 103, 249, 201, 252, 154, 69, 24, 48, 18, 63,
      ...> 65, 5, 10, 248, 37, 245, 101, 19, 118, 235, 82, 161, 165, 62, 43, 249, 237,
      ...> 223, 226, 253, 241, 155, 33, 45, 164, 50, 14, 176, 241, 3, 107, 12, 177, 47,
      ...> 20, 235, 147, 252, 28, 136, 226, 176, 180, 170, 85, 3, 151, 64, 10, 165, 166, 170,
      ...> 175, 231, 164, 69, 83, 150, 36, 135, 144, 20, 104, 226,
      ...> 183, 149, 250, 90, 117, 107, 162, 17, 63, 118, 229, 125, 15, 189, 245, 64,
      ...> 214, 93, 126, 179, 251, 41, 101, 249, 226, 180, 88, 241, 184, 154, 181, 156,
      ...> 178, 213, 132, 220, 31, 63, 23, 165, 174, 82, 182, 120, 142, 87, 34, 132,
      ...> 1, 0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
      ...> 186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99,
      ...> 0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
      ...> 133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17,
      ...> 63, 185, 153, 153, 153, 153, 153, 154, 0, 0, 0, 64, 47, 48, 215, 147, 153, 120, 199,
      ...> 102, 130, 0, 51, 138, 164, 146, 99, 2, 74, 116, 89, 117, 185, 72, 109, 10, 198, 124,
      ...> 44, 66, 126, 43, 85, 186, 105, 169, 159, 56, 129, 179, 207, 176, 97, 190, 162, 240,
      ...> 186, 164, 58, 41, 221, 27, 234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251,
      ...> 1, 0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
      ...> 115, 26, 63, 191, 152, 219, 245, 217, 29, 140, 42, 58, 104, 109, 108,
      ...> 64, 171, 239, 218, 149, 194, 162, 14, 64, 73, 160, 142, 149, 100, 135, 215, 48,
      ...> 133, 74, 61, 203, 113, 16, 163, 135, 41, 8, 227, 82, 131, 248, 200, 50, 113,
      ...> 195, 241, 169, 208, 28, 2, 53, 49, 141, 89, 99, 12, 189, 115, 188, 75, 11, 42,
      ...> 149, 223, 53, 234, 144, 115, 42, 99, 54, 94, 120, 25, 193, 0>>
      ...> |> UnirisCore.Transaction.deserialize()
      {
        %UnirisCore.Transaction{
          address: <<0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
            196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85>>,
          type: :transfer,
          timestamp: ~U[2020-06-24 12:56:33Z],
          data: %UnirisCore.TransactionData{},
          previous_public_key: <<0, 61, 250, 128, 151, 100, 231, 128, 158, 139, 88, 128, 68, 236, 240, 238, 116,
            186, 164, 87, 3, 60, 198, 21, 248, 64, 207, 58, 221, 192, 131, 180, 213>>,
          previous_signature: <<65, 66, 248, 246, 119, 69, 36, 103, 249, 201, 252, 154, 69, 24, 48, 18, 63,
           65, 5, 10, 248, 37, 245, 101, 19, 118, 235, 82, 161, 165, 62, 43, 249, 237,
           223, 226, 253, 241, 155, 33, 45, 164, 50, 14, 176, 241, 3, 107, 12, 177, 47,
           20, 235, 147, 252, 28, 136, 226, 176, 180, 170, 85, 3, 151>>,
          origin_signature: <<10, 165, 166, 170, 175, 231, 164, 69, 83, 150, 36, 135, 144, 20, 104, 226,
           183, 149, 250, 90, 117, 107, 162, 17, 63, 118, 229, 125, 15, 189, 245, 64,
           214, 93, 126, 179, 251, 41, 101, 249, 226, 180, 88, 241, 184, 154, 181, 156,
           178, 213, 132, 220, 31, 63, 23, 165, 174, 82, 182, 120, 142, 87, 34, 132>>,
          validation_stamp: %UnirisCore.Transaction.ValidationStamp{
             proof_of_work: <<0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
               186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99>>,
             proof_of_integrity: <<0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
               133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17>>,
             ledger_operations: %UnirisCore.Transaction.ValidationStamp.LedgerOperations{
                fee: 0.1,
                transaction_movements: [],
                node_movements: [],
                unspent_outputs: []
             },
             signature: <<47, 48, 215, 147, 153, 120, 199, 102, 130, 0, 51, 138, 164, 146, 99, 2, 74,
              116, 89, 117, 185, 72, 109, 10, 198, 124, 44, 66, 126, 43, 85, 186, 105, 169,
              159, 56, 129, 179, 207, 176, 97, 190, 162, 240, 186, 164, 58, 41, 221, 27,
              234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251>>
          },
          cross_validation_stamps: [
            %UnirisCore.Transaction.CrossValidationStamp{
                 node_public_key: <<0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
                   115, 26, 63, 191, 152, 219, 245, 217, 29, 140, 42, 58, 104, 109, 108>>,
                 signature: <<171, 239, 218, 149, 194, 162, 14, 64, 73, 160, 142, 149, 100, 135, 215, 48,
                   133, 74, 61, 203, 113, 16, 163, 135, 41, 8, 227, 82, 131, 248, 200, 50, 113,
                   195, 241, 169, 208, 28, 2, 53, 49, 141, 89, 99, 12, 189, 115, 188, 75, 11, 42,
                   149, 223, 53, 234, 144, 115, 42, 99, 54, 94, 120, 25, 193>>,
                 inconsistencies: []
            }
          ]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {transaction :: __MODULE__.t(), rest :: bitstring}
  def deserialize(_serialized_term = <<hash_algo::8, rest::bitstring>>) do
    address_size = Crypto.hash_size(hash_algo)
    <<address::binary-size(address_size), type::8, timestamp::32, rest::bitstring>> = rest
    {data, rest} = TransactionData.deserialize(rest)

    <<curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(curve_id)

    <<previous_public_key::binary-size(key_size), previous_signature_size::8,
      previous_signature::binary-size(previous_signature_size), origin_signature_size::8,
      origin_signature::binary-size(origin_signature_size), validated::8, rest::bitstring>> = rest

    tx = %__MODULE__{
      address: <<hash_algo::8>> <> address,
      type: parse_type(type),
      timestamp: DateTime.from_unix!(timestamp),
      data: data,
      previous_public_key: <<curve_id::8>> <> previous_public_key,
      previous_signature: previous_signature,
      origin_signature: origin_signature
    }

    case validated do
      0 ->
        {tx, rest}

      1 ->
        {validation_stamp, rest} = ValidationStamp.deserialize(rest)
        <<nb_cross_validations_stamps::8, rest::bitstring>> = rest

        {cross_validation_stamps, rest} =
          reduce_cross_validation_stamps(rest, nb_cross_validations_stamps, [])

        {
          %{
            tx
            | validation_stamp: validation_stamp,
              cross_validation_stamps: cross_validation_stamps
          },
          rest
        }
    end
  end

  defp reduce_cross_validation_stamps(rest, 0, _), do: {[], rest}

  defp reduce_cross_validation_stamps(rest, nb_stamps, acc) when length(acc) == nb_stamps do
    {Enum.reverse(acc), rest}
  end

  defp reduce_cross_validation_stamps(rest, nb_stamps, acc) do
    {stamp, rest} = CrossValidationStamp.deserialize(rest)
    reduce_cross_validation_stamps(rest, nb_stamps, [stamp | acc])
  end
end
