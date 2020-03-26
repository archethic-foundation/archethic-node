defmodule UnirisChain.Transaction do
  @moduledoc """
  Represents a transaction in the Uniris TransactionChain.

  Hosted on its own process for fast retrieval of information
  """
  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.ValidationStamp

  alias UnirisChain.TransactionRegistry
  alias UnirisChain.MetadataRegistry

  use Agent

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
          type: types(),
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
          {signature :: binary(), inconsistencies :: list(), public_key :: binary()}

  @typedoc """
  Represent a transaction been validated by coordinator and cross validation nodes.
  - Validation stamp: coordinator work result
  - Cross validation stamps: endorsements of the validation stamp from the coordinator
  """
  @type validated :: %{
          address: binary(),
          type: types(),
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
  @type types ::
          :identity
          | :keychain
          | :smart_contract
          | :node
          | :node_shared_secrets
          | :code

  @transaction_types [
    :identity,
    :keychain,
    :transfer,
    :node,
    :node_shared_secrets,
    :code,
    :beacon
  ]

  @doc """
  Create a new pending transaction by derivating keypair w/o predecence.

  The key generation and signature is protected by never givin the seed of the private key.

  The predecence is determined by the number of previous created transaction.
  If greater than 0, the keypair N-1 will be regenerated to sign the transaction (to compute the `previous_signature`).

  """
  @spec from_node_seed(
          transaction_type :: __MODULE__.types(),
          transaction_data :: Data.t(),
          index :: integer()
        ) :: Transaction.pending()
  def from_node_seed(
        type,
        data = %Data{} \\ %Data{},
        index \\ 0
      )
      when type in @transaction_types and is_number(index) do
    # Derivate previous and next keys
    previous_public_key = Crypto.node_public_key(index)
    next_public_key = Crypto.node_public_key(index + 1)

    transaction = %{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: DateTime.utc_now() |> DateTime.to_unix(),
      data: data,
      previous_public_key: previous_public_key
    }

    # Sign with the previous private key to ensure the integrity
    prev_sig =
      Crypto.sign_with_node_key(
        Map.take(transaction, [:address, :type, :timestamp, :data]),
        index
      )

    transaction = Map.put(transaction, :previous_signature, prev_sig)

    # Sign the transaction with a random origin signature to ensure the authorization
    origin_sig = Crypto.sign_with_origin_key(transaction)
    struct(__MODULE__, Map.put(transaction, :origin_signature, origin_sig))
  end

  @spec from_seed(
          seed :: binary(),
          transaction_type :: Transaction.types(),
          transaction_data :: Data.t(),
          index :: integer()
        ) :: Transaction.pending()
  def from_seed(
        seed,
        type,
        data = %Data{} \\ %Data{},
        index \\ 0
      )
      when is_binary(seed) and type in @transaction_types and is_number(index) do
    # Derivate previous and next keys
    {previous_public_key, previous_private_key} = Crypto.derivate_keypair(seed, index)
    {next_public_key, _} = Crypto.derivate_keypair(seed, index + 1)

    transaction = %{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: DateTime.utc_now() |> DateTime.to_unix(),
      data: data,
      previous_public_key: previous_public_key
    }

    # Sign with the previous private key to ensure the integrity
    prev_sig =
      Crypto.sign(
        Map.take(transaction, [:address, :type, :timestamp, :data]),
        previous_private_key
      )

    transaction = Map.put(transaction, :previous_signature, prev_sig)

    # Sign the transaction with a random origin signature to ensure the authorization
    origin_sig = Crypto.sign_with_origin_key(transaction)
    struct(__MODULE__, Map.put(transaction, :origin_signature, origin_sig))
  end

  @doc """
  Determines if the pending transaction integrity is valid
  """
  @spec valid_pending_transaction?(__MODULE__.pending()) :: boolean()
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

  def start_link(tx = %__MODULE__{address: address, type: type}) do
    Agent.start_link(
      fn ->
        case type do
          :node_shared_secret ->
            Registry.register(MetadataRegistry, :node_shared_secrets, [])
            tx

          :node ->
            Registry.register(MetadataRegistry, :node, [])
            tx
          _ ->
            case tx.data.ledger do
              %{uco: %Data.Ledger.UCO{transfers: uco_transfers}} ->
                Enum.map(uco_transfers, fn %Data.Ledger.Transfer{to: recipient} ->
                  recipient
                end)
                |> Enum.each(&Registry.register(MetadataRegistry, {:unspent_output, &1}, []))

                tx

              _ ->
                tx
            end
        end
      end,
      name: via_tuple(address)
    )
  end

  def get(pid) do
    Agent.get(pid, & &1)
  end

  defp via_tuple(address) do
    {:via, Registry, {TransactionRegistry, address}}
  end
end
