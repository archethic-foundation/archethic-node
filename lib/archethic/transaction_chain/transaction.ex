defmodule ArchEthic.TransactionChain.Transaction do
  @moduledoc """
  Represents the main unit of the ArchEthic network and its Transaction Chain.

  Blocks are reduce to its unitary form to provide high scalability, avoiding double spending attack and chain integrity
  """

  alias ArchEthic.Crypto

  alias __MODULE__.CrossValidationStamp
  alias __MODULE__.ValidationStamp
  alias __MODULE__.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

  defstruct [
    :address,
    :type,
    :data,
    :previous_public_key,
    :previous_signature,
    :origin_signature,
    :validation_stamp,
    cross_validation_stamps: [],
    version: 1
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
          | :origin_shared_secrets
          | :node_rewards
          | :beacon
          | :beacon_summary
          | :oracle
          | :oracle_summary
          | :code_proposal
          | :code_approval
          | :keychain
          | :keychain_access
          | :transfer
          | :nft
          | :hosting

  @transaction_types [
    :node,
    :node_shared_secrets,
    :origin_shared_secrets,
    :beacon,
    :beacon_summary,
    :oracle,
    :oracle_summary,
    :node_rewards,
    :code_proposal,
    :code_approval,
    :keychain,
    :keychain_access,
    :transfer,
    :hosting,
    :nft
  ]

  @doc """
  List all the supported transaction types
  """
  @spec types() :: list(transaction_type())
  def types, do: @transaction_types

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
      address: Crypto.hash(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction()
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
      address: Crypto.hash(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction(previous_private_key)
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
      address: Crypto.hash(next_public_key),
      type: type,
      data: data,
      previous_public_key: previous_public_key
    }
    |> previous_sign_transaction(previous_private_key)
    |> origin_sign_transaction()
  end

  defp get_transaction_public_keys(:node_shared_secrets) do
    key_index = Crypto.number_of_node_shared_secrets_keys()
    previous_public_key = Crypto.node_shared_secrets_public_key(key_index)
    next_public_key = Crypto.node_shared_secrets_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  defp get_transaction_public_keys(:node_rewards) do
    key_index = Crypto.number_of_network_pool_keys()
    previous_public_key = Crypto.network_pool_public_key(key_index)
    next_public_key = Crypto.network_pool_public_key(key_index + 1)
    {previous_public_key, next_public_key}
  end

  defp get_transaction_public_keys(_) do
    previous_public_key = Crypto.previous_node_public_key()
    next_public_key = Crypto.next_node_public_key()
    {previous_public_key, next_public_key}
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

  defp previous_sign_transaction(tx = %__MODULE__{type: :node_rewards}) do
    key_index = Crypto.number_of_network_pool_keys()

    previous_signature =
      tx
      |> extract_for_previous_signature()
      |> serialize()
      |> Crypto.sign_with_network_pool_key(key_index)

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

  @doc """
  Sign a transaction with a previous private key
  """
  @spec previous_sign_transaction(t(), Crypto.key()) :: t()
  def previous_sign_transaction(tx = %__MODULE__{}, private_key) when is_binary(private_key) do
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
      |> Crypto.sign_with_first_node_key()

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
  def serialize_type(:origin_shared_secrets), do: 2
  def serialize_type(:beacon), do: 3
  def serialize_type(:beacon_summary), do: 4
  def serialize_type(:oracle), do: 5
  def serialize_type(:oracle_summary), do: 6
  def serialize_type(:code_proposal), do: 7
  def serialize_type(:code_approval), do: 8
  def serialize_type(:node_rewards), do: 9

  # User transaction's type
  def serialize_type(:keychain), do: 255
  def serialize_type(:keychain_access), do: 254
  def serialize_type(:transfer), do: 253
  def serialize_type(:hosting), do: 252
  def serialize_type(:nft), do: 251

  @doc """
  Parse a serialize transaction type
  """
  @spec parse_type(non_neg_integer()) :: transaction_type()
  # Network transaction's type
  def parse_type(0), do: :node
  def parse_type(1), do: :node_shared_secrets
  def parse_type(2), do: :origin_shared_secrets
  def parse_type(3), do: :beacon
  def parse_type(4), do: :beacon_summary
  def parse_type(5), do: :oracle
  def parse_type(6), do: :oracle_summary
  def parse_type(7), do: :code_proposal
  def parse_type(8), do: :code_approval
  def parse_type(9), do: :node_rewards

  # User transaction's type
  def parse_type(255), do: :keychain
  def parse_type(254), do: :keychain_access
  def parse_type(253), do: :transfer
  def parse_type(252), do: :hosting
  def parse_type(251), do: :nft

  @doc """
  Determines if a transaction type is a network one
  """
  @spec network_type?(transaction_type()) :: boolean()
  def network_type?(:node), do: true
  def network_type?(:node_shared_secrets), do: true
  def network_type?(:origin_shared_secrets), do: true
  def network_type?(:code_proposal), do: true
  def network_type?(:code_approval), do: true
  def network_type?(:oracle), do: true
  def network_type?(:oracle_summary), do: true
  def network_type?(:node_rewards), do: true
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

  ## Examples

      iex> %Transaction{
      ...>  data: %TransactionData{
      ...>    ledger: %Ledger{
      ...>      uco: %UCOLedger{
      ...>        transfers: [
      ...>          %UCOLedger.Transfer{to: "@Alice1", amount: 10}
      ...>        ]
      ...>      },
      ...>      nft: %NFTLedger{
      ...>        transfers: [
      ...>          %NFTLedger.Transfer{to: "@Alice1", amount: 3, nft: "@BobNFT"}
      ...>        ]
      ...>      }
      ...>    }
      ...>  }
      ...> } |> Transaction.get_movements()
      [
        %TransactionMovement{
          to: "@Alice1", amount: 10, type: :UCO,
        },
        %TransactionMovement{
          to: "@Alice1", amount: 3, type: {:NFT, "@BobNFT"},
        }
      ]
  """
  @spec get_movements(t()) :: list(TransactionMovement.t())
  def get_movements(%__MODULE__{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{transfers: uco_transfers},
            nft: %NFTLedger{transfers: nft_transfers}
          }
        }
      }) do
    Enum.map(uco_transfers, &%TransactionMovement{to: &1.to, amount: &1.amount, type: :UCO}) ++
      Enum.map(
        nft_transfers,
        &%TransactionMovement{to: &1.to, amount: &1.amount, type: {:NFT, &1.nft}}
      )
  end

  @doc """
  Return the previous transaction address from the previous public key
  """
  @spec previous_address(t()) :: binary()
  def previous_address(%__MODULE__{previous_public_key: previous_public_key}),
    do: Crypto.hash(previous_public_key)

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
  @spec verify_previous_signature?(t()) :: boolean()
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
  Serialize a transaction into binary format

  ## Examples

      iex> %Transaction{
      ...>   version: 1,
      ...>   address: <<0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
      ...>     196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
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
      ...>   validation_stamp: %ValidationStamp{
      ...>      timestamp: ~U[2020-06-26 06:37:04Z],
      ...>      proof_of_work: <<0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
      ...>        186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99>>,
      ...>      proof_of_integrity: <<0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
      ...>        133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17>>,
      ...>      proof_of_election: <<84, 71, 95, 29, 105, 203, 16, 245, 173, 18, 126, 216, 43, 32, 143, 223, 71,
      ...>        184, 247, 123, 166, 185, 137, 6, 151, 77, 251, 163, 132, 132, 235, 136>>,
      ...>      ledger_operations: %LedgerOperations{
      ...>         fee: 10_000_000,
      ...>         transaction_movements: [],
      ...>         node_movements: [],
      ...>         unspent_outputs: []
      ...>      },
      ...>      recipients: [],
      ...>      errors: [],
      ...>      signature: <<47, 48, 215, 147, 153, 120, 199, 102, 130, 0, 51, 138, 164, 146, 99, 2, 74,
      ...>       116, 89, 117, 185, 72, 109, 10, 198, 124, 44, 66, 126, 43, 85, 186, 105, 169,
      ...>       159, 56, 129, 179, 207, 176, 97, 190, 162, 240, 186, 164, 58, 41, 221, 27,
      ...>       234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251>>
      ...>   },
      ...>   cross_validation_stamps: [
      ...>     %CrossValidationStamp{
      ...>          node_public_key: <<0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
      ...>            115, 26, 63, 191, 152, 219, 245, 217, 29, 140, 42, 58, 104, 109, 108>>,
      ...>          signature: <<171, 239, 218, 149, 194, 162, 14, 64, 73, 160, 142, 149, 100, 135, 215, 48,
      ...>            133, 74, 61, 203, 113, 16, 163, 135, 41, 8, 227, 82, 131, 248, 200, 50, 113,
      ...>            195, 241, 169, 208, 28, 2, 53, 49, 141, 89, 99, 12, 189, 115, 188, 75, 11, 42,
      ...>            149, 223, 53, 234, 144, 115, 42, 99, 54, 94, 120, 25, 193>>,
      ...>          inconsistencies: []
      ...>     }
      ...>   ]
      ...> }
      ...> |> Transaction.serialize()
      <<
      # Version
      0, 0, 0, 1,
      # Address
      0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
      196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85,
      # Transaction type (transfer),
      253,
      # Code size
      0, 0, 0, 0,
      # Content size
      0, 0, 0, 0,
      # Nb keys,
      0,
      # Nb UCO transfers
      0,
      # Nb NFT transfers
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
      # Validation Stamp timestamp
      0, 0, 1, 114, 239, 88, 10, 128,
      # Proof of work
      0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
      186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99,
      # Proof of integrity
      0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
      133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17,
      # Proof of election
      84, 71, 95, 29, 105, 203, 16, 245, 173, 18, 126, 216, 43, 32, 143, 223, 71,
      184, 247, 123, 166, 185, 137, 6, 151, 77, 251, 163, 132, 132, 235, 136,
      # Fee
      0, 0, 0, 0, 0, 152, 150, 128,
      # Nb transaction movements
      0,
      # Nb node movements
      0,
      # Nb unspent outputs,
      0,
      # Nb resolved recipients,
      0,
      # Nb errors
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
      # Nb inconsistencies
      0
      >>
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
      TransactionData.serialize(data)::binary>>
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
      TransactionData.serialize(data)::binary, previous_public_key::binary,
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
      TransactionData.serialize(data)::binary, previous_public_key::binary,
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
      TransactionData.serialize(data)::binary, previous_public_key::binary,
      byte_size(previous_signature)::8, previous_signature::binary,
      byte_size(origin_signature)::8, origin_signature::binary, 1::8,
      ValidationStamp.serialize(validation_stamp)::bitstring, length(cross_validation_stamps)::8,
      cross_validation_stamps_bin::binary>>
  end

  @doc """
  Deserialize an encoded transaction

  ## Examples

      iex> <<0, 0, 0, 1, 0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
      ...> 196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85, 253,
      ...> 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 61, 250, 128, 151, 100, 231, 128, 158, 139,
      ...> 88, 128, 68, 236, 240, 238, 116, 186, 164, 87, 3, 60, 198, 21, 248, 64, 207, 58, 221, 192,
      ...> 131, 180, 213, 64, 65, 66, 248, 246, 119, 69, 36, 103, 249, 201, 252, 154, 69, 24, 48, 18, 63,
      ...> 65, 5, 10, 248, 37, 245, 101, 19, 118, 235, 82, 161, 165, 62, 43, 249, 237,
      ...> 223, 226, 253, 241, 155, 33, 45, 164, 50, 14, 176, 241, 3, 107, 12, 177, 47,
      ...> 20, 235, 147, 252, 28, 136, 226, 176, 180, 170, 85, 3, 151, 64, 10, 165, 166, 170,
      ...> 175, 231, 164, 69, 83, 150, 36, 135, 144, 20, 104, 226,
      ...> 183, 149, 250, 90, 117, 107, 162, 17, 63, 118, 229, 125, 15, 189, 245, 64,
      ...> 214, 93, 126, 179, 251, 41, 101, 249, 226, 180, 88, 241, 184, 154, 181, 156,
      ...> 178, 213, 132, 220, 31, 63, 23, 165, 174, 82, 182, 120, 142, 87, 34, 132,
      ...> 1, 0, 0, 1, 114, 239, 88, 10, 128, 0, 0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
      ...> 186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99,
      ...> 0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
      ...> 133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17,
      ...> 74, 224, 26, 42, 253, 85, 104, 246, 72, 244, 189, 182, 165, 94, 92, 20, 166,
      ...> 149, 124, 246, 219, 170, 160, 168, 206, 214, 236, 215, 211, 121, 95, 149, 132,
      ...> 136, 114, 244, 132, 44, 255, 222, 98, 76, 247, 125, 45, 170, 95, 51, 46, 229,
      ...> 21, 32, 226, 99, 16, 5, 107, 207, 32, 240, 23, 85, 219, 247,
      ...> 0, 0, 0, 0, 0, 152, 150, 128, 0, 0, 0, 0, 0, 64, 47, 48, 215, 147, 153, 120, 199,
      ...> 102, 130, 0, 51, 138, 164, 146, 99, 2, 74, 116, 89, 117, 185, 72, 109, 10, 198, 124,
      ...> 44, 66, 126, 43, 85, 186, 105, 169, 159, 56, 129, 179, 207, 176, 97, 190, 162, 240,
      ...> 186, 164, 58, 41, 221, 27, 234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251,
      ...> 1, 0, 0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
      ...> 115, 26, 63, 191, 152, 219, 245, 217, 29, 140, 42, 58, 104, 109, 108,
      ...> 64, 171, 239, 218, 149, 194, 162, 14, 64, 73, 160, 142, 149, 100, 135, 215, 48,
      ...> 133, 74, 61, 203, 113, 16, 163, 135, 41, 8, 227, 82, 131, 248, 200, 50, 113,
      ...> 195, 241, 169, 208, 28, 2, 53, 49, 141, 89, 99, 12, 189, 115, 188, 75, 11, 42,
      ...> 149, 223, 53, 234, 144, 115, 42, 99, 54, 94, 120, 25, 193, 0>>
      ...> |> Transaction.deserialize()
      {
        %Transaction{
          version: 1,
          address: <<0, 62, 198, 74, 197, 246, 83, 6, 174, 95, 223, 107, 92, 12, 36, 93, 197, 197,
            196, 186, 34, 34, 134, 184, 95, 181, 113, 255, 93, 134, 197, 243, 85>>,
          type: :transfer,
          data: %TransactionData{},
          previous_public_key: <<0, 0, 61, 250, 128, 151, 100, 231, 128, 158, 139, 88, 128, 68, 236, 240, 238, 116,
            186, 164, 87, 3, 60, 198, 21, 248, 64, 207, 58, 221, 192, 131, 180, 213>>,
          previous_signature: <<65, 66, 248, 246, 119, 69, 36, 103, 249, 201, 252, 154, 69, 24, 48, 18, 63,
           65, 5, 10, 248, 37, 245, 101, 19, 118, 235, 82, 161, 165, 62, 43, 249, 237,
           223, 226, 253, 241, 155, 33, 45, 164, 50, 14, 176, 241, 3, 107, 12, 177, 47,
           20, 235, 147, 252, 28, 136, 226, 176, 180, 170, 85, 3, 151>>,
          origin_signature: <<10, 165, 166, 170, 175, 231, 164, 69, 83, 150, 36, 135, 144, 20, 104, 226,
           183, 149, 250, 90, 117, 107, 162, 17, 63, 118, 229, 125, 15, 189, 245, 64,
           214, 93, 126, 179, 251, 41, 101, 249, 226, 180, 88, 241, 184, 154, 181, 156,
           178, 213, 132, 220, 31, 63, 23, 165, 174, 82, 182, 120, 142, 87, 34, 132>>,
          validation_stamp: %ValidationStamp{
             timestamp: ~U[2020-06-26 06:37:04.000Z],
             proof_of_work: <<0, 0, 212, 52, 50, 200, 144, 139, 192, 177, 99, 145, 174, 178, 113, 229, 251, 170,
               186, 184, 109, 13, 200, 136, 34, 241, 99, 99, 210, 172, 143, 104, 160, 99>>,
             proof_of_integrity: <<0, 199, 216, 73, 158, 82, 76, 158, 8, 215, 22, 186, 166, 45, 153, 17, 22, 251,
               133, 212, 35, 220, 155, 242, 198, 93, 133, 134, 244, 226, 122, 87, 17>>,
             proof_of_election: <<74, 224, 26, 42, 253, 85, 104, 246, 72, 244, 189, 182, 165, 94, 92, 20, 166,
              149, 124, 246, 219, 170, 160, 168, 206, 214, 236, 215, 211, 121, 95, 149, 132,
              136, 114, 244, 132, 44, 255, 222, 98, 76, 247, 125, 45, 170, 95, 51, 46, 229,
              21, 32, 226, 99, 16, 5, 107, 207, 32, 240, 23, 85, 219, 247>>,
             ledger_operations: %LedgerOperations{
                fee: 10_000_000,
                transaction_movements: [],
                node_movements: [],
                unspent_outputs: []
             },
             errors: [],
             recipients: [],
             signature: <<47, 48, 215, 147, 153, 120, 199, 102, 130, 0, 51, 138, 164, 146, 99, 2, 74,
              116, 89, 117, 185, 72, 109, 10, 198, 124, 44, 66, 126, 43, 85, 186, 105, 169,
              159, 56, 129, 179, 207, 176, 97, 190, 162, 240, 186, 164, 58, 41, 221, 27,
              234, 185, 105, 75, 81, 238, 158, 13, 150, 184, 31, 247, 79, 251>>
          },
          cross_validation_stamps: [
            %CrossValidationStamp{
                 node_public_key: <<0, 0, 253, 187, 69, 83, 77, 33, 173, 15, 226, 88, 230, 68, 235, 114, 146, 89, 221,
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
  @spec deserialize(bitstring()) :: {transaction :: t(), rest :: bitstring}
  def deserialize(_serialized_term = <<version::32, hash_algo::8, rest::bitstring>>) do
    address_size = Crypto.hash_size(hash_algo)
    <<address::binary-size(address_size), type::8, rest::bitstring>> = rest

    {data, rest} = TransactionData.deserialize(rest)

    <<curve_id::8, origin_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(curve_id)

    <<previous_public_key::binary-size(key_size), previous_signature_size::8,
      previous_signature::binary-size(previous_signature_size), origin_signature_size::8,
      origin_signature::binary-size(origin_signature_size), validated::8, rest::bitstring>> = rest

    tx = %__MODULE__{
      version: version,
      address: <<hash_algo::8, address::binary>>,
      type: parse_type(type),
      data: data,
      previous_public_key: <<curve_id::8, origin_id::8, previous_public_key::binary>>,
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

  @spec to_map(t()) :: map()
  def to_map(tx = %__MODULE__{}) do
    %{
      version: tx.version,
      address: tx.address,
      type: Atom.to_string(tx.type),
      data: TransactionData.to_map(tx.data),
      previous_public_key: tx.previous_public_key,
      previous_signature: tx.previous_signature,
      origin_signature: tx.origin_signature,
      validation_stamp: ValidationStamp.to_map(tx.validation_stamp),
      cross_validation_stamps:
        Enum.map(tx.cross_validation_stamps || [], &CrossValidationStamp.to_map/1)
    }
  end

  @spec from_map(map()) :: t()
  def from_map(tx = %{}) do
    type =
      case Map.get(tx, :type) do
        nil ->
          nil

        type ->
          String.to_atom(type)
      end

    %__MODULE__{
      version: Map.get(tx, :version),
      address: Map.get(tx, :address),
      type: type,
      data: Map.get(tx, :data, %TransactionData{}) |> TransactionData.from_map(),
      previous_public_key: Map.get(tx, :previous_public_key),
      previous_signature: Map.get(tx, :previous_signature),
      origin_signature: Map.get(tx, :origin_signature),
      validation_stamp: Map.get(tx, :validation_stamp) |> ValidationStamp.from_map(),
      cross_validation_stamps:
        (Map.get(tx, :cross_validation_stamps) || [])
        |> Enum.map(&CrossValidationStamp.from_map/1)
    }
  end
end
