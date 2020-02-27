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
          | :origin_shared_key
          | :node_shared_key
          | :code

  @transaction_types [
    :identity,
    :keychain,
    :transfer,
    :node,
    :origin_shared_key,
    :node_shared_key,
    :code
  ]

  @doc """
  Create a new pending transaction by derivating keypair w/o predecence.

  The predecence is determined by the number of previous created transaction.
  If greater than 0, the keypair N-1 will be regenerated to sign the transaction (to compute the `previous_signature`).


  ## Examples
     ```
     iex> UnirisChain.Transaction.new(:transfer,
     ...>   %UnirisChain.Transaction.Data{
     ...>     ledger: %UnirisChain.Transaction.Data.Ledger.UCO{
     ...>       transfers: [%UnirisChain.Transaction.Data.Ledger.Transfer{ to: "", amount: 10}]
     ...>      }
     ...>   }
     ...> )
     %UnirisChain.Transaction{
       address: <<0, 28, 183, 200, 78, 111, 143, 127, 108, 149, 238, 111, 230, 51,
         217, 17, 224, 61, 219, 111, 134, 10, 75, 220, 49, 98, 10, 42, 62, 121, 121,
         47, 121>>,
       data: %UnirisChain.Transaction.Data{
         code: "",
         content: "",
         keys: %{},
         ledger: %UnirisChain.Transaction.Data.Ledger.UCO{
           fee: nil,
           transfers: [
             %UnirisChain.Transaction.Data.Ledger.Transfer{
                amount: 10,
                conditions: nil,
                to: ""
             }
           ]
         },
         recipients: []
       },
       origin_signature: <<224, 241, 112, 2, 58, 254, 225, 87, 97, 223, 126, 96,
       184, 172, 93, 151, 187, 137, 176, 28, 16, 151, 99, 143, 171, 56, 73, 87,
       133, 35, 81, 46, 128, 98, 236, 74, 127, 243, 180, 115, 216, 234, 235, 125,
       65, 141, 65, 244, 180, 152, 233, 200, 5, 173, 145, 89, 193, 207, 203, 49,
       217, 190, 195, 2>>, 
       previous_public_key: <<0, 193, 80, 142, 239, 14, 128, 108, 123, 101, 138, 2,
        155, 99, 63, 100, 54, 144, 168, 232, 240, 161, 13, 59, 177, 89, 80, 17,
        197, 49, 14, 7, 174>>,
       previous_signature: <<230, 64, 254, 226, 145, 242, 253, 122, 62, 196, 201,
         212, 236, 198, 61, 110, 95, 26, 45, 66, 204, 227, 91, 48, 130, 100, 177,
         143, 180, 229, 26, 191, 67, 7, 189, 58, 214, 236, 222, 30, 191, 47, 117,
         138, 253, 231, 160, 24, 143, 125, 84, 163, 126, 60, 19, 164, 116, 27, 42,
         188, 165, 248, 68, 8>>,
       timestamp: 1582635339,
       type: :transfer
     }
     ```
  """
  @spec new(
          transaction_type :: Transaction.types(),
          transaction_data :: Data.t(),
          timestamp :: integer(),
          nb_transaction :: non_neg_integer() | 0
        ) :: Transaction.pending()
  def new(
        type,
        data = %Data{},
        timestamp \\ DateTime.utc_now() |> DateTime.to_unix(),
        nb_transaction \\ 0
      )
      when nb_transaction >= 0 and
             type in @transaction_types do
    previous_public_key = Crypto.derivate_keypair(nb_transaction, persistence: true)
    next_public_key = Crypto.derivate_keypair(nb_transaction + 1, persistence: true)

    transaction = %{
      address: Crypto.hash(next_public_key),
      type: type,
      timestamp: timestamp,
      data: data,
      previous_public_key: previous_public_key
    }

    prev_sig =
      Crypto.sign(Map.take(transaction, [:address, :type, :timestamp, :data]),
        with: :node,
        as: :previous
      )

    transaction = Map.put(transaction, :previous_signature, prev_sig)
    origin_sig = Crypto.sign(transaction, with: :origin, as: :random)
    struct(__MODULE__, Map.put(transaction, :origin_signature, origin_sig))
  end

  @doc """
  Determines if the pending transaction integrity is valid
  """
  @spec valid_pending_transaction?(__MODULE__.pending()) :: boolean()
  def valid_pending_transaction?(tx = %__MODULE__{}) do
    with true <- Crypto.valid_hash?(tx.address),
         true <- tx.type in @transaction_types,
         true <- Crypto.valid_public_key?(tx.previous_public_key),
         true <- tx.address != Crypto.hash(tx.previous_public_key),
         true <-
           Crypto.verify(
             tx.previous_signature,
             Map.take(tx, [:address, :type, :timestamp, :data]),
             tx.previous_public_key
           ) do
      # TODO: perform additional checks regarding the data block
      true
    else
      _ ->
        false
    end
  end
end
