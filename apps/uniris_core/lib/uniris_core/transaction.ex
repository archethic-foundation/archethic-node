defmodule UnirisCore.Transaction do
  @moduledoc """
  Represents the main unit of the Uniris network and its Transaction Chain.

  Blocks are reduce to its unitary form to provide high scalability, avoiding double spending attack and chain integrity
  """
  alias __MODULE__.ValidationStamp
  alias UnirisCore.TransactionData
  alias UnirisCore.Crypto

  @enforce_keys [
    :address,
    :type,
    :timestamp,
    :data,
    :previous_public_key,
    :previous_signature,
    :origin_signature
  ]
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
  - Type: transaction type (`UnirisChain.Transaction.types()`)
  - Timestamp: creation date of the transaction
  - Data: transaction data zone (identity, keychain, smart contract, etc.)
  - Previous signature: signature from the previous public key
  - Previous public key: previous generated public key matching the previous signature
  - Origin signature: signature from the device which originated the transaction (used in the Proof of work)
  """
  @type pending :: %{
          address: binary(),
          type: transaction_type(),
          timestamp: non_neg_integer(),
          data: Data.t(),
          previous_public_key: binary(),
          previous_signature: binary(),
          origin_signature: binary()
        }

  @typedoc """
  Represent a cross validation stamp coming from a cross validation node
  - Signature is made from the validation stamp if no inconsistencies or made from the list of inconsistencies
  - Inconsistencies is a list of errors found by a cross validation node from the validation stamp
  """
  @type cross_validation_stamp ::
          {signature :: binary(), inconsistencies :: list(atom()),
           public_key :: UnirisCrypto.key()}

  @typedoc """
  Represent a transaction been validated by coordinator and cross validation nodes.
  - Validation stamp: coordinator work result
  - Cross validation stamps: endorsements of the validation stamp from the coordinator
  """
  @type validated :: %{
          address: binary(),
          type: transaction_type(),
          timestamp: non_neg_integer(),
          data: Data.t(),
          previous_public_key: binary(),
          previous_signature: binary(),
          origin_signature: binary(),
          validation_stamp: ValidationStamp.t(),
          cross_validation_stamps: list(cross_validation_stamp())
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

  @spec new(transaction_type(), TransactionData.t()) :: __MODULE__.pending()
  def new(type, data = %TransactionData{}) when type in [:node, :node_shared_secrets, :beacon] do
    {previous_public_key, next_public_key} = get_transaction_public_keys(type)

    %{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: DateTime.utc_now(),
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction()
    |> origin_sign_transaction()
    |> cast()
  end

  @spec new(transaction_type(), TransactionData.t(), binary(), non_neg_integer()) ::
          __MODULE__.pending()
  def new(type, data = %TransactionData{}, seed, index) when type in @transaction_types do
    {previous_public_key, previous_private_key} = Crypto.derivate_keypair(seed, index)
    {next_public_key, _} = Crypto.derivate_keypair(seed, index + 1)

    %{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: DateTime.utc_now(),
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction(previous_private_key)
    |> origin_sign_transaction()
    |> cast
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

  defp previous_sign_transaction(tx = %{type: :node}) do
    key_index = Crypto.number_of_node_keys()

    previous_signature =
      Crypto.sign_with_node_key(
        Map.take(tx, [:address, :type, :timestamp, :data]),
        key_index
      )

    Map.put(tx, :previous_signature, previous_signature)
  end

  # TODO: use the sync seed in the node shared secrets
  defp previous_sign_transaction(tx = %{type: :beacon}) do
    key_index = Crypto.number_of_node_keys()

    previous_signature =
      Crypto.sign_with_node_key(
        Map.take(tx, [:address, :type, :timestamp, :data]),
        key_index
      )

    Map.put(tx, :previous_signature, previous_signature)
  end

  defp previous_sign_transaction(tx = %{type: :node_shared_secrets}) do
    key_index = Crypto.number_of_node_shared_secrets_keys()

    previous_signature =
      Crypto.sign_with_node_shared_secrets_key(
        Map.take(tx, [:address, :type, :timestamp, :data]),
        key_index
      )

    Map.put(tx, :previous_signature, previous_signature)
  end

  defp previous_sign_transaction(tx = %{}, private_key) do
    previous_signature =
      Crypto.sign(
        Map.take(tx, [:address, :type, :timestamp, :data]),
        private_key
      )

    Map.put(tx, :previous_signature, previous_signature)
  end

  defp origin_sign_transaction(tx) do
    origin_sig = Crypto.sign_with_node_key(tx, 0)
    Map.put(tx, :origin_signature, origin_sig)
  end

  defp cast(fields) do
    struct(__MODULE__, fields)
  end

  @spec valid_pending_transaction?(Transaction.pending()) :: boolean()
  def valid_pending_transaction?(tx = %__MODULE__{}) do
    cond do
      !Crypto.valid_hash?(tx.address) ->
        false

      tx.type not in @transaction_types ->
        false

      !Crypto.valid_public_key?(tx.previous_public_key) ->
        false

      !Crypto.verify(
        tx.previous_signature,
        Map.take(tx, [:address, :type, :timestamp, :data]),
        tx.previous_public_key
      ) ->
        false

      true ->
        # TODO: perform additional checks regarding the data block
        true
    end
  end

  def serialize_type(:identity), do: 0
  def serialize_type(:keychain), do: 1
  def serialize_type(:transfer), do: 2
  def serialize_type(:node), do: 3
  def serialize_type(:node_shared_secrets), do: 4
  def serialize_type(:origin_shared_secrets), do: 5
  def serialize_type(:code), do: 6
  def serialize_type(:beacon), do: 7
  def serialize_type(:hosting), do: 8

  def parse_type(0), do: :identity
  def parse_type(1), do: :keychain
  def parse_type(2), do: :transfer
  def parse_type(3), do: :node
  def parse_type(4), do: :node_shared_secrets
  def parse_type(5), do: :origin_shared_secrets
  def parse_type(6), do: :code
  def parse_type(7), do: :beacon
  def parse_type(8), do: :hosting

  def network_type?(:node), do: true
  def network_type?(:node_shared_secrets), do: true
  def network_type?(:origin_shared_secrets), do: true
  def network_type?(:code), do: true
  def network_type?(_), do: false

  def pending(tx = %__MODULE__{}) do
    struct!(
      __MODULE__,
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
