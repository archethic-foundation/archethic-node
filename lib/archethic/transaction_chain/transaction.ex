defmodule Archethic.TransactionChain.Transaction do
  @moduledoc """
  Represents the main unit of the Archethic network and its Transaction Chain.

  Blocks are reduce to its unitary form to provide high scalability, avoiding double spending attack and chain integrity
  """

  alias Archethic.Crypto

  alias __MODULE__.CrossValidationStamp
  alias __MODULE__.ValidationStamp
  alias __MODULE__.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.Utils

  @token_creation_schema :archethic
                         |> Application.app_dir("priv/json-schemas/token-core.json")
                         |> File.read!()
                         |> Jason.decode!()
                         |> ExJsonSchema.Schema.resolve()

  @token_resupply_schema :archethic
                         |> Application.app_dir("priv/json-schemas/token-resupply.json")
                         |> File.read!()
                         |> Jason.decode!()
                         |> ExJsonSchema.Schema.resolve()

  @unit_uco 100_000_000
  @version 1

  defstruct [
    :address,
    :type,
    :data,
    :previous_public_key,
    :previous_signature,
    :origin_signature,
    :validation_stamp,
    cross_validation_stamps: [],
    version: @version
  ]

  @typedoc """
  Represent a transaction in pending validation
  - Address: hash of the new generated public key for the given transaction
  - Type: transaction type
  - Data: transaction data zone (identity, keychain, smart contract, etc.)
  - Previous signature: signature from the previous public key
  - Previous public key: previous generated public key matching the previous signature
  - Origin signature: signature from the device which originated the transaction (used in the Proof of work)
  - Version: version of the transaction (used for backward compatiblity)

  When the transaction is validated the following fields are filled:
  - Validation stamp: coordinator work result
  - Cross validation stamps: endorsements of the validation stamp from the coordinator
  """
  @type t() :: %__MODULE__{
          address: binary(),
          type: transaction_type(),
          data: TransactionData.t(),
          previous_public_key: nil | Crypto.key(),
          previous_signature: nil | binary(),
          origin_signature: nil | binary(),
          validation_stamp: nil | ValidationStamp.t(),
          cross_validation_stamps: nil | list(CrossValidationStamp.t()),
          version: pos_integer()
        }

  @typedoc """
  Supported transaction types
  """
  @type transaction_type ::
          :node
          | :node_shared_secrets
          | :node_rewards
          | :mint_rewards
          | :oracle
          | :oracle_summary
          | :code_proposal
          | :code_approval
          | :keychain
          | :keychain_access
          | :transfer
          | :token
          | :hosting
          | :origin
          | :data
          | :contract

  @transaction_types [
    :node,
    :node_shared_secrets,
    :oracle,
    :oracle_summary,
    :node_rewards,
    :mint_rewards,
    :code_proposal,
    :code_approval,
    :keychain,
    :keychain_access,
    :transfer,
    :hosting,
    :token,
    :origin,
    :data,
    :contract
  ]

  @doc """
  List all the supported transaction types
  """
  @spec types() :: list(transaction_type())
  def types, do: @transaction_types

  def version, do: @version

  @doc """
  Create a new pending transaction using the Crypto keystore to find out
  the seed and the transaction index

  The first node private key is used as origin private key
  """
  @spec new(type :: transaction_type(), data :: TransactionData.t()) ::
          t()
  def new(type, data = %TransactionData{}) do
    {previous_public_key, next_public_key} = get_transaction_public_keys(type)

    %__MODULE__{
      address: Crypto.derive_address(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction()
    |> origin_sign_transaction()
  end

  @spec new(type :: transaction_type(), data :: TransactionData.t(), non_neg_integer()) ::
          t()
  def new(type, data = %TransactionData{}, index) do
    {previous_public_key, next_public_key} = get_transaction_public_keys(type, index)

    %__MODULE__{
      address: Crypto.derive_address(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction(index)
    |> origin_sign_transaction()
  end

  @doc """
  Create a new pending transaction

  The first node private key is used as origin private key
  """
  @spec new(
          type :: transaction_type(),
          data :: TransactionData.t(),
          seed :: binary(),
          index :: non_neg_integer()
        ) :: t()
  def new(type, data = %TransactionData{}, seed, index, curve \\ Crypto.default_curve())
      when type in @transaction_types and is_binary(seed) and is_integer(index) and index >= 0 do
    {previous_public_key, previous_private_key} = Crypto.derive_keypair(seed, index, curve)
    {next_public_key, _} = Crypto.derive_keypair(seed, index + 1, curve)

    %__MODULE__{
      address: Crypto.derive_address(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction_with_key(previous_private_key)
    |> origin_sign_transaction()
  end

  @doc """
  Create transaction with the direct use of private and public keys
  """
  @spec new_with_keys(
          transaction_type(),
          TransactionData.t(),
          Crypto.key(),
          Crypto.key(),
          Crypto.key()
        ) :: t()
  def new_with_keys(
        type,
        data = %TransactionData{},
        previous_private_key,
        previous_public_key,
        next_public_key
      ) do
    %__MODULE__{
      address: Crypto.derive_address(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction_with_key(previous_private_key)
    |> origin_sign_transaction()
  end

  defp get_transaction_public_keys(:node_shared_secrets) do
    key_index = Crypto.number_of_node_shared_secrets_keys()
    do_get_transaction_public_keys(:node_shared_secrets, key_index)
  end

  defp get_transaction_public_keys(type) when type in [:node_rewards, :mint_rewards] do
    key_index = Crypto.number_of_network_pool_keys()
    do_get_transaction_public_keys(type, key_index)
  end

  defp get_transaction_public_keys(_type) do
    previous_public_key = Crypto.previous_node_public_key()
    next_public_key = Crypto.next_node_public_key()
    {previous_public_key, next_public_key}
  end

  defp get_transaction_public_keys(:node_shared_secrets, key_index) do
    do_get_transaction_public_keys(:node_shared_secrets, key_index)
  end

  defp get_transaction_public_keys(type, key_index) when type in [:node_rewards, :mint_rewards] do
    do_get_transaction_public_keys(type, key_index)
  end

  defp do_get_transaction_public_keys(:node_shared_secrets, key_index) do
    previous_public_key = Crypto.node_shared_secrets_public_key(key_index)
    next_public_key = Crypto.node_shared_secrets_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  defp do_get_transaction_public_keys(type, key_index)
       when type in [:node_rewards, :mint_rewards] do
    previous_public_key = Crypto.network_pool_public_key(key_index)
    next_public_key = Crypto.network_pool_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  defp previous_sign_transaction(tx = %__MODULE__{type: :node_shared_secrets}) do
    key_index = Crypto.number_of_node_shared_secrets_keys()
    previous_signature = do_previous_sign_transaction(tx, key_index)
    %{tx | previous_signature: previous_signature}
  end

  defp previous_sign_transaction(tx = %__MODULE__{type: type})
       when type in [:node_rewards, :mint_rewards] do
    key_index = Crypto.number_of_network_pool_keys()
    previous_signature = do_previous_sign_transaction(tx, key_index)

    %{tx | previous_signature: previous_signature}
  end

  defp previous_sign_transaction(tx = %__MODULE__{}) do
    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign_with_previous_node_key()

    %{tx | previous_signature: previous_signature}
  end

  defp previous_sign_transaction(tx = %__MODULE__{type: :node_shared_secrets}, key_index) do
    previous_signature = do_previous_sign_transaction(tx, key_index)
    %{tx | previous_signature: previous_signature}
  end

  defp previous_sign_transaction(tx = %__MODULE__{type: type}, key_index)
       when type in [:node_rewards, :mint_rewards] do
    previous_signature = do_previous_sign_transaction(tx, key_index)
    %{tx | previous_signature: previous_signature}
  end

  defp do_previous_sign_transaction(tx = %__MODULE__{type: :node_shared_secrets}, key_index) do
    tx
    |> extract_for_previous_signature()
    |> serialize()
    |> Crypto.sign_with_node_shared_secrets_key(key_index)
  end

  defp do_previous_sign_transaction(tx = %__MODULE__{type: type}, key_index)
       when type in [:node_rewards, :mint_rewards] do
    tx
    |> extract_for_previous_signature()
    |> serialize()
    |> Crypto.sign_with_network_pool_key(key_index)
  end

  @doc """
  Sign a transaction with a previous private key
  """
  @spec previous_sign_transaction_with_key(t(), Crypto.key()) :: t()
  def previous_sign_transaction_with_key(tx = %__MODULE__{}, private_key)
      when is_binary(private_key) do
    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign(private_key)

    %{tx | previous_signature: previous_signature}
  end

  @doc """
  Sign a transaction with an origin private key
  """
  @spec origin_sign_transaction(t(), Crypto.key()) :: t()
  def origin_sign_transaction(tx) do
    origin_sig =
      tx
      |> extract_for_origin_signature
      |> serialize()
      |> Crypto.sign_with_origin_node_key()

    %{tx | origin_signature: origin_sig}
  end

  def origin_sign_transaction(tx, origin_private_key) do
    origin_sig =
      tx
      |> extract_for_origin_signature
      |> serialize()
      |> Crypto.sign(origin_private_key)

    %{tx | origin_signature: origin_sig}
  end

  @doc """
  Extract the transaction payload for the previous signature including address, type and data
  """
  @spec extract_for_previous_signature(t()) :: t()
  def extract_for_previous_signature(tx = %__MODULE__{}) do
    %__MODULE__{
      address: tx.address,
      type: tx.type,
      data: tx.data
    }
  end

  @doc """
  Extract the transaction payload for the origin signature including address
  type data, previous_public_key and previous_signature
  """
  @spec extract_for_origin_signature(t()) :: t()
  def extract_for_origin_signature(tx = %__MODULE__{}) do
    %__MODULE__{
      address: tx.address,
      type: tx.type,
      data: tx.data,
      previous_public_key: tx.previous_public_key,
      previous_signature: tx.previous_signature
    }
  end

  @doc """
  Serialize transaction type
  """
  @spec serialize_type(transaction_type()) :: non_neg_integer()
  # Network transaction's type
  def serialize_type(:node), do: 0
  def serialize_type(:node_shared_secrets), do: 1
  def serialize_type(:origin), do: 2
  def serialize_type(:oracle), do: 3
  def serialize_type(:oracle_summary), do: 4
  def serialize_type(:code_proposal), do: 5
  def serialize_type(:code_approval), do: 6
  def serialize_type(:node_rewards), do: 7

  def serialize_type(:mint_rewards),
    do: 8

  # User transaction's type
  def serialize_type(:keychain), do: 255
  def serialize_type(:keychain_access), do: 254
  def serialize_type(:transfer), do: 253
  def serialize_type(:hosting), do: 252
  def serialize_type(:token), do: 251
  def serialize_type(:data), do: 250
  def serialize_type(:contract), do: 249

  @doc """
  Parse a serialize transaction type
  """
  @spec parse_type(non_neg_integer()) :: transaction_type()
  # Network transaction's type
  def parse_type(0), do: :node
  def parse_type(1), do: :node_shared_secrets
  def parse_type(2), do: :origin
  def parse_type(3), do: :oracle
  def parse_type(4), do: :oracle_summary
  def parse_type(5), do: :code_proposal
  def parse_type(6), do: :code_approval
  def parse_type(7), do: :node_rewards
  def parse_type(8), do: :mint_rewards

  # User transaction's type
  def parse_type(255), do: :keychain
  def parse_type(254), do: :keychain_access
  def parse_type(253), do: :transfer
  def parse_type(252), do: :hosting
  def parse_type(251), do: :token
  def parse_type(250), do: :data
  def parse_type(249), do: :contract

  @doc """
  Determines if a transaction type is a network one
  """
  @spec network_type?(transaction_type()) :: boolean()
  def network_type?(:node), do: true
  def network_type?(:node_shared_secrets), do: true
  def network_type?(:origin), do: true
  def network_type?(:code_proposal), do: true
  def network_type?(:code_approval), do: true
  def network_type?(:oracle), do: true
  def network_type?(:oracle_summary), do: true
  def network_type?(:node_rewards), do: true
  def network_type?(:mint_rewards), do: true
  def network_type?(_), do: false

  @doc """
  Extract the pending transaction fields from a transaction
  """
  @spec to_pending(t()) :: t()
  def to_pending(tx = %__MODULE__{}) do
    %{tx | validation_stamp: nil, cross_validation_stamps: nil}
  end

  @doc """
  Get the transfers and transaction movements from a transaction
  """
  @spec get_movements(t()) :: list(TransactionMovement.t())
  def get_movements(%__MODULE__{
        type: type,
        address: tx_address,
        data: %TransactionData{
          content: content,
          ledger: %Ledger{
            uco: %UCOLedger{transfers: uco_transfers},
            token: %TokenLedger{transfers: token_transfers}
          }
        }
      }) do
    List.flatten([
      Enum.map(uco_transfers, &%TransactionMovement{to: &1.to, amount: &1.amount, type: :UCO}),
      Enum.map(
        token_transfers,
        &%TransactionMovement{
          to: &1.to,
          amount: &1.amount,
          type: {:token, &1.token_address, &1.token_id}
        }
      ),
      case type do
        :token -> get_movements_from_token_transaction(tx_address, content)
        :mint_reward -> get_movements_from_token_transaction(tx_address, content)
        _ -> []
      end
    ])
  end

  @doc """
  Return the previous transaction address from the previous public key
  """
  @spec previous_address(t()) :: binary()
  def previous_address(%__MODULE__{previous_public_key: previous_public_key}),
    do: Crypto.derive_address(previous_public_key)

  @doc """
  Determines if the atomic commitment has been reached

  ## Examples

      iex> %Transaction{
      ...>   cross_validation_stamps: [
      ...>      %CrossValidationStamp{inconsistencies: []},
      ...>      %CrossValidationStamp{inconsistencies: [:invalid_ledger_operations]},
      ...>      %CrossValidationStamp{inconsistencies: [:invalid_proof_of_work]}
      ...>   ]
      ...> } |> Transaction.atomic_commitment?
      false

      iex> %Transaction{
      ...>   cross_validation_stamps: [
      ...>      %CrossValidationStamp{inconsistencies: []},
      ...>      %CrossValidationStamp{inconsistencies: []},
      ...>      %CrossValidationStamp{inconsistencies: []}
      ...>   ]
      ...> } |> Transaction.atomic_commitment?
      true
  """
  @spec atomic_commitment?(t()) :: boolean()
  def atomic_commitment?(%__MODULE__{cross_validation_stamps: stamps}) when is_list(stamps) do
    nb_distinct_inconsistencies =
      stamps
      |> Enum.dedup_by(& &1.inconsistencies)
      |> length

    nb_distinct_inconsistencies == 1
  end

  def atomic_commitment?(%__MODULE__{cross_validation_stamps: _}), do: false

  @doc """
  Verify if the public key match the origin signature of the transaction
  """
  @spec verify_origin_signature?(t(), Crypto.key()) :: boolean()
  def verify_origin_signature?(%__MODULE__{}, ""), do: false

  def verify_origin_signature?(tx = %__MODULE__{origin_signature: origin_signature}, public_key)
      when is_binary(public_key) do
    raw_tx =
      tx
      |> extract_for_origin_signature()
      |> serialize()

    Crypto.verify?(origin_signature, raw_tx, public_key)
  end

  @doc """
  Determines if the previous signature is valid
  """
  @spec verify_previous_signature?(tx :: t()) :: boolean()
  def verify_previous_signature?(
        tx = %__MODULE__{previous_public_key: prev_key, previous_signature: prev_sig}
      ) do
    raw_tx =
      tx
      |> extract_for_previous_signature()
      |> serialize()

    Crypto.verify?(prev_sig, raw_tx, prev_key)
  end

  @doc """
  Receive in paramater a tx and a list with multiple list of public_keys
  the list of list is used during self repair for replication attestation V1
  otherwise each list contains only 1 public key (the last one of the node)

  Return true if the signature are valid based on received public keys
  """
  @spec valid_stamps_signature?(tx :: t(), list_of_public_keys :: list(list(Crypto.key()))) ::
          boolean()
  def valid_stamps_signature?(
        %__MODULE__{validation_stamp: stamp, cross_validation_stamps: cross_stamps},
        list_of_public_keys
      ) do
    public_keys = List.flatten(list_of_public_keys)

    # TODO: we need to ensure that the coordinator node is not the same than the cross validation nodes.
    # This control must be done only for distributed workflow (more than one validation node)
    # The list of list will be usefull for this control.

    with true <- valid_coordinator?(stamp, public_keys),
         true <- different_cross_stamps?(cross_stamps) do
      valid_cross_signature?(stamp, cross_stamps, public_keys)
    else
      _ -> false
    end
  end

  defp valid_coordinator?(stamp, public_keys),
    do: Enum.any?(public_keys, &ValidationStamp.valid_signature?(stamp, &1))

  defp different_cross_stamps?(cross_stamps),
    do: cross_stamps == Enum.uniq_by(cross_stamps, & &1.node_public_key)

  defp valid_cross_signature?(stamp, cross_stamps, public_keys),
    do:
      Enum.all?(
        cross_stamps,
        fn cross_stamp = %CrossValidationStamp{node_public_key: node_public_key} ->
          Enum.any?(public_keys, &(&1 == node_public_key)) and
            CrossValidationStamp.valid_signature?(cross_stamp, stamp)
        end
      )

  @doc """
  Serialize a transaction into binary format

  ## Examples

      iex> %Transaction{
      ...>   address: <<0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42, 196,
      ...>     25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217, 180,
      ...>     32>>,
      ...>   cross_validation_stamps: [],
      ...>   data: %Archethic.TransactionChain.TransactionData{
      ...>     code: "",
      ...>     content: <<0, 98, 12, 24, 6, 0, 0, 0, 1, 0, 0, 238, 143, 251, 13, 151, 68,
      ...>       48, 247, 25, 179, 245, 118, 171, 203, 76, 243, 214, 84, 147, 214, 174,
      ...>       206, 214, 92, 218, 100, 225, 114, 163, 26, 223, 186, 0, 0, 1, 126, 255,
      ...>       61, 177, 215, 1, 0, 1, 0, 234, 193, 62, 27, 61, 132, 121, 178, 119, 20,
      ...>       124, 88, 206, 36, 125, 163, 108, 229, 219, 181, 143, 253, 246, 237, 238,
      ...>       21, 79, 9, 230, 172, 0, 95, 0, 0, 0, 0, 0>>,
      ...>     ledger: %Archethic.TransactionChain.TransactionData.Ledger{
      ...>       token: %Archethic.TransactionChain.TransactionData.TokenLedger{transfers: []},
      ...>       uco: %Archethic.TransactionChain.TransactionData.UCOLedger{transfers: []}
      ...>     },
      ...>     ownerships: [],
      ...>     recipients: []
      ...>   },
      ...>   origin_signature: <<163, 184, 57, 242, 100, 203, 42, 179, 241, 235, 35, 167,
      ...>     197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247, 119, 139, 211, 85,
      ...>     134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6, 137, 87, 32, 13,
      ...>     241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66, 132, 213, 105,
      ...>     229, 14, 2>>,
      ...>   previous_public_key: <<0, 0, 84, 200, 174, 114, 81, 219, 237, 219, 237, 222,
      ...>     27, 55, 149, 8, 235, 248, 37, 69, 1, 8, 128, 139, 184, 80, 114, 82, 40, 61,
      ...>     25, 169, 26, 69>>,
      ...>   previous_signature: <<83, 137, 109, 48, 131, 81, 37, 65, 81, 210, 9, 87, 246,
      ...>     107, 10, 101, 24, 218, 230, 38, 212, 35, 242, 216, 223, 83, 224, 11, 168,
      ...>     158, 5, 198, 202, 48, 233, 171, 107, 127, 70, 206, 98, 145, 93, 119, 98, 58,
      ...>     79, 206, 161, 21, 251, 218, 6, 44, 55, 133, 13, 122, 125, 219, 122, 131, 73,
      ...>     6>>,
      ...>   type: :oracle,
      ...>   validation_stamp: %Archethic.TransactionChain.Transaction.ValidationStamp{
      ...>     ledger_operations: %Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations{
      ...>       fee: 0,
      ...>       transaction_movements: [],
      ...>       unspent_outputs: []
      ...>     },
      ...>     proof_of_election: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...>       0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...>       0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
      ...>     proof_of_integrity: <<0, 188, 101, 205, 214, 203, 136, 90, 130, 68, 147, 79,
      ...>       76, 46, 139, 19, 189, 123, 142, 29, 113, 208, 111, 136, 227, 252, 213,
      ...>       180, 80, 70, 158, 27, 148>>,
      ...>     proof_of_work: <<0, 0, 29, 150, 125, 113, 178, 225, 53, 200, 66, 6, 221,
      ...>       209, 8, 181, 146, 90, 44, 217, 156, 142, 188, 90, 181, 216, 253, 46, 201,
      ...>       64, 12, 227, 201, 138>>,
      ...>     recipients: [],
      ...>     signature: <<187, 93, 5, 6, 190, 102, 244, 88, 141, 142, 7, 138, 178, 77,
      ...>       128, 21, 95, 29, 222, 145, 211, 18, 48, 16, 185, 69, 209, 146, 56, 26,
      ...>       106, 191, 101, 56, 15, 99, 52, 179, 212, 169, 7, 30, 131, 39, 100, 115,
      ...>       73, 176, 212, 121, 236, 91, 94, 118, 108, 9, 228, 44, 237, 157, 90, 243,
      ...>       90, 6>>,
      ...>     timestamp: ~U[2022-02-15 21:15:50.000Z],
      ...>     protocol_version: current_protocol_version()
      ...>   },
      ...>   version: current_transaction_version()
      ...> }
      ...> |> Transaction.serialize()
      <<current_transaction_version()::32, 0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42,
          196, 25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217,
          180, 32, 3, 0, 0, 0, 0, 0, 0, 0, 92, 0, 98, 12, 24, 6, 0, 0, 0, 1, 0, 0, 238,
          143, 251, 13, 151, 68, 48, 247, 25, 179, 245, 118, 171, 203, 76, 243, 214, 84,
          147, 214, 174, 206, 214, 92, 218, 100, 225, 114, 163, 26, 223, 186, 0, 0, 1,
          126, 255, 61, 177, 215, 1, 0, 1, 0, 234, 193, 62, 27, 61, 132, 121, 178, 119,
          20, 124, 88, 206, 36, 125, 163, 108, 229, 219, 181, 143, 253, 246, 237, 238,
          21, 79, 9, 230, 172, 0, 95, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 84,
          200, 174, 114, 81, 219, 237, 219, 237, 222, 27, 55, 149, 8, 235, 248, 37, 69,
          1, 8, 128, 139, 184, 80, 114, 82, 40, 61, 25, 169, 26, 69, 64, 83, 137, 109,
          48, 131, 81, 37, 65, 81, 210, 9, 87, 246, 107, 10, 101, 24, 218, 230, 38, 212,
          35, 242, 216, 223, 83, 224, 11, 168, 158, 5, 198, 202, 48, 233, 171, 107, 127,
          70, 206, 98, 145, 93, 119, 98, 58, 79, 206, 161, 21, 251, 218, 6, 44, 55, 133,
          13, 122, 125, 219, 122, 131, 73, 6, 64, 163, 184, 57, 242, 100, 203, 42, 179,
          241, 235, 35, 167, 197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247,
          119, 139, 211, 85, 134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6,
          137, 87, 32, 13, 241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66,
          132, 213, 105, 229, 14, 2, 1, current_protocol_version()::32, 0, 0, 1, 126, 255, 61, 215, 112, 0, 0, 29, 150,
          125, 113, 178, 225, 53, 200, 66, 6, 221, 209, 8, 181, 146, 90, 44, 217, 156,
          142, 188, 90, 181, 216, 253, 46, 201, 64, 12, 227, 201, 138, 0, 188, 101, 205,
          214, 203, 136, 90, 130, 68, 147, 79, 76, 46, 139, 19, 189, 123, 142, 29, 113,
          208, 111, 136, 227, 252, 213, 180, 80, 70, 158, 27, 148, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 64, 187, 93, 5, 6,
          190, 102, 244, 88, 141, 142, 7, 138, 178, 77, 128, 21, 95, 29, 222, 145, 211,
          18, 48, 16, 185, 69, 209, 146, 56, 26, 106, 191, 101, 56, 15, 99, 52, 179,
          212, 169, 7, 30, 131, 39, 100, 115, 73, 176, 212, 121, 236, 91, 94, 118, 108,
          9, 228, 44, 237, 157, 90, 243, 90, 6, 0>>

  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        version: version,
        address: address,
        type: type,
        data: data,
        previous_public_key: nil,
        previous_signature: nil,
        origin_signature: nil,
        validation_stamp: nil
      }) do
    <<version::32, address::binary, serialize_type(type)::8,
      TransactionData.serialize(data, version)::binary>>
  end

  def serialize(%__MODULE__{
        version: version,
        address: address,
        type: type,
        data: data,
        previous_public_key: previous_public_key,
        previous_signature: previous_signature,
        origin_signature: nil,
        validation_stamp: nil
      }) do
    <<version::32, address::binary, serialize_type(type)::8,
      TransactionData.serialize(data, version)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary>>
  end

  def serialize(%__MODULE__{
        version: version,
        address: address,
        type: type,
        data: data,
        previous_public_key: previous_public_key,
        previous_signature: previous_signature,
        origin_signature: origin_signature,
        validation_stamp: nil
      }) do
    <<version::32, address::binary, serialize_type(type)::8,
      TransactionData.serialize(data, version)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary,
      byte_size(origin_signature)::8, origin_signature::binary, 0::8>>
  end

  def serialize(%__MODULE__{
        version: version,
        address: address,
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

    <<version::32, address::binary, serialize_type(type)::8,
      TransactionData.serialize(data, version)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary,
      byte_size(origin_signature)::8, origin_signature::binary, 1::8,
      ValidationStamp.serialize(validation_stamp)::bitstring, length(cross_validation_stamps)::8,
      cross_validation_stamps_bin::binary>>
  end

  @doc """
  Deserialize an encoded transaction

  ## Examples

      iex> <<current_transaction_version()::32, 0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42,
      ...> 196, 25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217,
      ...> 180, 32, 3, 0, 0, 0, 0, 0, 0, 0, 92, 0, 98, 12, 24, 6, 0, 0, 0, 1, 0, 0, 238,
      ...> 143, 251, 13, 151, 68, 48, 247, 25, 179, 245, 118, 171, 203, 76, 243, 214, 84,
      ...> 147, 214, 174, 206, 214, 92, 218, 100, 225, 114, 163, 26, 223, 186, 0, 0, 1,
      ...> 126, 255, 61, 177, 215, 1, 0, 1, 0, 234, 193, 62, 27, 61, 132, 121, 178, 119,
      ...> 20, 124, 88, 206, 36, 125, 163, 108, 229, 219, 181, 143, 253, 246, 237, 238,
      ...> 21, 79, 9, 230, 172, 0, 95, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 84,
      ...> 200, 174, 114, 81, 219, 237, 219, 237, 222, 27, 55, 149, 8, 235, 248, 37, 69,
      ...> 1, 8, 128, 139, 184, 80, 114, 82, 40, 61, 25, 169, 26, 69, 64, 83, 137, 109,
      ...> 48, 131, 81, 37, 65, 81, 210, 9, 87, 246, 107, 10, 101, 24, 218, 230, 38, 212,
      ...> 35, 242, 216, 223, 83, 224, 11, 168, 158, 5, 198, 202, 48, 233, 171, 107, 127,
      ...> 70, 206, 98, 145, 93, 119, 98, 58, 79, 206, 161, 21, 251, 218, 6, 44, 55, 133,
      ...> 13, 122, 125, 219, 122, 131, 73, 6, 64, 163, 184, 57, 242, 100, 203, 42, 179,
      ...> 241, 235, 35, 167, 197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247,
      ...> 119, 139, 211, 85, 134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6,
      ...> 137, 87, 32, 13, 241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66,
      ...> 132, 213, 105, 229, 14, 2, 1, 0, 0, 0, 2, 0, 0, 1, 126, 255, 61, 215, 112, 0, 0, 29, 150,
      ...> 125, 113, 178, 225, 53, 200, 66, 6, 221, 209, 8, 181, 146, 90, 44, 217, 156,
      ...> 142, 188, 90, 181, 216, 253, 46, 201, 64, 12, 227, 201, 138, 0, 188, 101, 205,
      ...> 214, 203, 136, 90, 130, 68, 147, 79, 76, 46, 139, 19, 189, 123, 142, 29, 113,
      ...> 208, 111, 136, 227, 252, 213, 180, 80, 70, 158, 27, 148, 0, 0, 0, 0, 0, 0, 0,
      ...> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 64, 187, 93, 5, 6,
      ...> 190, 102, 244, 88, 141, 142, 7, 138, 178, 77, 128, 21, 95, 29, 222, 145, 211,
      ...> 18, 48, 16, 185, 69, 209, 146, 56, 26, 106, 191, 101, 56, 15, 99, 52, 179,
      ...> 212, 169, 7, 30, 131, 39, 100, 115, 73, 176, 212, 121, 236, 91, 94, 118, 108,
      ...> 9, 228, 44, 237, 157, 90, 243, 90, 6, 0>>
      ...> |> Transaction.deserialize()
      {
        %Transaction{
          address: <<0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42, 196,
            25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217, 180,
            32>>,
          cross_validation_stamps: [],
          data: %Archethic.TransactionChain.TransactionData{
            code: "",
            content: <<0, 98, 12, 24, 6, 0, 0, 0, 1, 0, 0, 238, 143, 251, 13, 151, 68,
              48, 247, 25, 179, 245, 118, 171, 203, 76, 243, 214, 84, 147, 214, 174,
              206, 214, 92, 218, 100, 225, 114, 163, 26, 223, 186, 0, 0, 1, 126, 255,
              61, 177, 215, 1, 0, 1, 0, 234, 193, 62, 27, 61, 132, 121, 178, 119, 20,
              124, 88, 206, 36, 125, 163, 108, 229, 219, 181, 143, 253, 246, 237, 238,
              21, 79, 9, 230, 172, 0, 95, 0, 0, 0, 0, 0>>,
            ledger: %Archethic.TransactionChain.TransactionData.Ledger{
              token: %Archethic.TransactionChain.TransactionData.TokenLedger{transfers: []},
              uco: %Archethic.TransactionChain.TransactionData.UCOLedger{transfers: []}
            },
            ownerships: [],
            recipients: []
          },
          origin_signature: <<163, 184, 57, 242, 100, 203, 42, 179, 241, 235, 35, 167,
            197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247, 119, 139, 211, 85,
            134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6, 137, 87, 32, 13,
            241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66, 132, 213, 105,
            229, 14, 2>>,
          previous_public_key: <<0, 0, 84, 200, 174, 114, 81, 219, 237, 219, 237, 222,
            27, 55, 149, 8, 235, 248, 37, 69, 1, 8, 128, 139, 184, 80, 114, 82, 40, 61,
            25, 169, 26, 69>>,
          previous_signature: <<83, 137, 109, 48, 131, 81, 37, 65, 81, 210, 9, 87, 246,
            107, 10, 101, 24, 218, 230, 38, 212, 35, 242, 216, 223, 83, 224, 11, 168,
            158, 5, 198, 202, 48, 233, 171, 107, 127, 70, 206, 98, 145, 93, 119, 98, 58,
            79, 206, 161, 21, 251, 218, 6, 44, 55, 133, 13, 122, 125, 219, 122, 131, 73,
            6>>,
          type: :oracle,
          validation_stamp: %Archethic.TransactionChain.Transaction.ValidationStamp{
            ledger_operations: %Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations{
              fee: 0,
              transaction_movements: [],
              unspent_outputs: []
            },
            proof_of_election: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
            proof_of_integrity: <<0, 188, 101, 205, 214, 203, 136, 90, 130, 68, 147, 79,
              76, 46, 139, 19, 189, 123, 142, 29, 113, 208, 111, 136, 227, 252, 213,
              180, 80, 70, 158, 27, 148>>,
            proof_of_work: <<0, 0, 29, 150, 125, 113, 178, 225, 53, 200, 66, 6, 221,
              209, 8, 181, 146, 90, 44, 217, 156, 142, 188, 90, 181, 216, 253, 46, 201,
              64, 12, 227, 201, 138>>,
            recipients: [],
            signature: <<187, 93, 5, 6, 190, 102, 244, 88, 141, 142, 7, 138, 178, 77,
              128, 21, 95, 29, 222, 145, 211, 18, 48, 16, 185, 69, 209, 146, 56, 26,
              106, 191, 101, 56, 15, 99, 52, 179, 212, 169, 7, 30, 131, 39, 100, 115,
              73, 176, 212, 121, 236, 91, 94, 118, 108, 9, 228, 44, 237, 157, 90, 243,
              90, 6>>,
            timestamp: ~U[2022-02-15 21:15:50.000Z],
            protocol_version: 2
          },
          version: 1
        },
        ""
      }

  """
  @spec deserialize(bitstring()) :: {transaction :: t(), rest :: bitstring}
  def deserialize(_serialized_term = <<version::32, rest::bitstring>>) do
    {address, <<type::8, rest::bitstring>>} = Utils.deserialize_address(rest)

    {data, rest} = TransactionData.deserialize(rest, version)

    {previous_public_key,
     <<previous_signature_size::8, previous_signature::binary-size(previous_signature_size),
       origin_signature_size::8, origin_signature::binary-size(origin_signature_size),
       validated::8, rest::bitstring>>} = Utils.deserialize_public_key(rest)

    tx = %__MODULE__{
      version: version,
      address: address,
      type: parse_type(type),
      data: data,
      previous_public_key: previous_public_key,
      previous_signature: previous_signature,
      origin_signature: origin_signature
    }

    case validated do
      0 ->
        {tx, rest}

      1 ->
        {validation_stamp, <<nb_cross_validations_stamps::8, rest::bitstring>>} =
          ValidationStamp.deserialize(rest)

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

  @spec to_map(t()) :: map()
  def to_map(tx = %__MODULE__{}) do
    %{
      version: tx.version,
      address: tx.address,
      type: Atom.to_string(tx.type),
      data: TransactionData.to_map(tx.data),
      previous_public_key: tx.previous_public_key,
      previous_address: previous_address(tx),
      previous_signature: tx.previous_signature,
      origin_signature: tx.origin_signature,
      validation_stamp: ValidationStamp.to_map(tx.validation_stamp),
      cross_validation_stamps:
        Enum.map(tx.cross_validation_stamps || [], &CrossValidationStamp.to_map/1)
    }
  end

  @spec cast(map()) :: t()
  def cast(tx = %{}) do
    type =
      case Map.get(tx, :type) do
        nil ->
          nil

        type when is_binary(type) ->
          String.to_existing_atom(type)

        type when is_atom(type) ->
          type
      end

    %__MODULE__{
      version: Map.get(tx, :version),
      address: Map.get(tx, :address),
      type: type,
      data: Map.get(tx, :data, %TransactionData{}) |> TransactionData.cast(),
      previous_public_key: Map.get(tx, :previous_public_key),
      previous_signature: Map.get(tx, :previous_signature),
      origin_signature: Map.get(tx, :origin_signature),
      validation_stamp: Map.get(tx, :validation_stamp) |> ValidationStamp.cast(),
      cross_validation_stamps:
        (Map.get(tx, :cross_validation_stamps) || [])
        |> Enum.map(&CrossValidationStamp.cast/1)
    }
  end

  defp get_movements_from_token_transaction(tx_address, tx_content) do
    case Jason.decode(tx_content) do
      {:ok, json} ->
        cond do
          ExJsonSchema.Validator.valid?(@token_creation_schema, json) ->
            get_movements_from_token_creation(tx_address, json)

          ExJsonSchema.Validator.valid?(@token_resupply_schema, json) ->
            get_movements_from_token_resupply(json)

          true ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp get_movements_from_token_creation(tx_address, %{"recipients" => recipients, "type" => type}) do
    fungible? = type == "fungible"

    Enum.map(recipients, fn recipient = %{"to" => address_hex, "amount" => amount} ->
      token_id = Map.get(recipient, "token_id", 0)
      address = Base.decode16!(address_hex, case: :mixed)

      if not fungible? and amount != @unit_uco do
        nil
      else
        %TransactionMovement{
          to: address,
          amount: amount,
          type: {:token, tx_address, token_id}
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_movements_from_token_creation(_tx_address, _json), do: []

  defp get_movements_from_token_resupply(%{
         "recipients" => recipients,
         "token_reference" => token_reference
       }) do
    Enum.map(recipients, fn %{"to" => address_hex, "amount" => amount} ->
      token_address = Base.decode16!(token_reference, case: :mixed)
      address = Base.decode16!(address_hex, case: :mixed)

      %TransactionMovement{
        to: address,
        amount: amount,
        type: {:token, token_address, 0}
      }
    end)
  end

  defp get_movements_from_token_resupply(_json), do: []
end
