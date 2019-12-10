defmodule UnirisChain.Transaction do
  @moduledoc """
  Represents a transaction in the Uniris TransactionChain.

  Each transaction also has an additional signature corresponding to
  the signature of the device that generated the transaction.

  This signature is used inside the Proof of Work mechanism and can be integrated as
  a necessary condition for the validation of a transaction
  """
  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.ValidationStamp

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
          cross_validation_stamps: list(binary())
        }

  @typedoc """
  Supported transaction types
  """
  @type types ::
          :identity
          | :keychain
          | :smart_contract
          | :node
          | :origin_shared_key
          | :node_shared_key
          | :code

  @doc """
  Return the list of supported transaction type
  """
  @spec types() :: types()
  def types do
    [
      :identity,
      :keychain,
      :smart_contract,
      :node,
      :origin_shared_key,
      :node_shared_key,
      :code
    ]
  end

  @doc """
  Create a new pending transaction by derivating keypair w/o predecence.

  The predecence is determined by the number of previous created transaction.
  If greater than 0, the keypair N-1 will be regenerated to sign the transaction (to compute the `previous_signature`).

  """
  @spec new(
          Transaction.types(),
          Data.t(),
          nb_transaction :: non_neg_integer() | 0
        ) :: {:ok, Transaction.pending()} | {:error, :invalid_type}
  def new(type, data = %Data{}, nb_transaction \\ 0)
      when is_atom(type) and is_integer(nb_transaction) and nb_transaction >= 0 do
    if type not in types() do
      {:error, :invalid_type}
    else
      with tx = %__MODULE__{} <- build_transaction(type, data, nb_transaction) do
        {:ok, tx}
      end
    end
  end

  defp build_transaction(type, data, nb_transaction) do
    with {:ok, current_pub} <- Crypto.last_public_key(:node),
         {:ok, next_pub} <-
           Crypto.derivate_keypair(nb_transaction + 1, storage_destination: :node) do
      transaction = %{
        address: Crypto.hash(next_pub),
        type: type,
        timestamp: DateTime.to_unix(DateTime.utc_now()),
        data: data,
        previous_public_key: current_pub
      }

      with {:ok, prev_sig} <-
             Crypto.sign(
               Map.take(transaction, [:address, :type, :timestamp, :data]),
               source: :node,
               label: :previous
             ),
           transaction <- Map.put(transaction, :previous_signature, prev_sig),
           {:ok, origin_sig} <- Crypto.sign(transaction, source: :origin, label: :last),
           transaction <- Map.put(transaction, :origin_signature, origin_sig) do
        struct!(__MODULE__, transaction)
      end
    end
  end

  @doc """
  Validate a pending transaction to ensure its integrity
  """
  @spec check_pending_integrity(pending()) ::
          :ok | {:error, :invalid_signature}
  def check_pending_integrity(tx = %__MODULE__{}) do
    Crypto.verify(
      tx.previous_signature,
      Map.take(tx, [:address, :type, :timestamp, :data]),
      tx.previous_public_key
    )
  end
end
