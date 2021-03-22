defmodule UnirisWeb.GraphQLSchema.TransactionType do
  @moduledoc false

  use Absinthe.Schema.Notation

  import_types(UnirisWeb.GraphQLSchema.DateTimeType)
  import_types(UnirisWeb.GraphQLSchema.HexType)
  import_types(UnirisWeb.GraphQLSchema.ContentType)
  import_types(UnirisWeb.GraphQLSchema.AddressType)

  alias UnirisWeb.GraphQLSchema.Resolver

  @desc "[Transaction] represents a unitary transaction in the Uniris network."
  object :transaction do
    field(:address, :hex)
    field(:timestamp, :timestamp)
    field(:type, :string)
    field(:data, :data)
    field(:previous_public_key, :hex)
    field(:previous_signature, :hex)
    field(:origin_signature, :hex)
    field(:validation_stamp, :validation_stamp)
    field(:cross_validation_stamps, list_of(:cross_validation_stamp))

    field :inputs, list_of(:transaction_input) do
      resolve(fn _, %{source: %{address: address}} ->
        {:ok, Resolver.get_inputs(address)}
      end)
    end

    field :chain_length, :integer do
      resolve(fn _, %{source: %{address: address}} ->
        {:ok, Resolver.get_chain_length(address)}
      end)
    end

    field :balance, :balance do
      resolve(fn _, %{source: %{address: address}} ->
        {:ok, Resolver.get_balance(address)}
      end)
    end
  end

  @desc """
  [TransactionData] represents the data section for every transaction.
  It includes:
  - Ledger: asset transfers
  - Code: smart contract code (hexadecimal),
  - Content: free zone for data hosting (string or hexadecimal)
  - Keys: Secrets and authorized public keys to decrypt the secret
  - Recipients: For non asset transfers, the list of recipients of the transaction (e.g Smart contract interactions)
  """
  object :data do
    field(:ledger, :ledger)
    field(:code, :string)
    field(:content, :content)
    field(:keys, :keys)
    field(:recipients, list_of(:hex))
  end

  @desc "[Ledger] represents the ledger operations to perform"
  object :ledger do
    field(:uco, :uco_ledger)
    field(:nft, :nft_ledger)
  end

  @desc "[UCOTransfer] represents the an asset transfer"
  object :uco_transfer do
    field(:to, :hex)
    field(:amount, :float)
  end

  @desc "[NFTTransfer] represents the an asset transfer"
  object :nft_transfer do
    field(:to, :hex)
    field(:amount, :float)
    field(:nft, :hex)
  end

  @desc "[UCOLedger] represents the transfers to perform on the UCO ledger"
  object :uco_ledger do
    field(:transfers, list_of(:uco_transfer))
  end

  @desc "[NFTLedger] represents the transfers to perform on the UCO ledger"
  object :nft_ledger do
    field(:transfers, list_of(:nft_transfer))
  end

  @desc "[Keys] represents a block to set secret and authorized public keys able to read the secret"
  object :keys do
    field(:secret, :hex)
    field(:authorized_keys, list_of(:authorized_key))
  end

  @desc """
  [AuthorizedKey] represents list of public keys with the encrypted secret for this given key.
  By decrypting this secret keys, the authorized public keys will be able to decrypt the secret
  """
  object :authorized_key do
    field(:public_key, :hex)
    field(:encrypted_key, :hex)
  end

  @desc """
  [ValidationStamp] represents the validation performs by the coordinator
  It includes:
  - Proof of work: Public key matching the origin signature
  - Proof of integrity: Hash of the previous proof of integrity and the transaction
  - Ledger operations: All the operations performed by the transaction
  - Signature: Coordinator signature of the stamp
  """
  object :validation_stamp do
    field(:proof_of_work, :hex)
    field(:proof_of_integrity, :hex)
    field(:ledger_operations, :ledger_operations)
    field(:signature, :hex)
  end

  @desc """
  [LedgerOperations] represents the ledger operations performed by the transaction
  It includes:
  - Transaction movements: assets transfers
  - Node movements: node rewards
  - Unspent outputs: remaining unspent outputs
  - Fee: transaction fee (distributed over the node rewards)
  """
  object :ledger_operations do
    field(:transaction_movements, list_of(:transaction_movement))
    field(:node_movements, list_of(:node_movement))
    field(:unspent_outputs, list_of(:unspent_output))
    field(:fee, :float)
  end

  @desc """
  [UnspentOutput] represents the remaining unspent output of the transaction.
  It includes:
  - From: transaction which send the amount of assets
  - Amount: asset amount
  - Type: UCO/NFT
  - NFT address: address of the NFT if the type is NFT
  """
  object :unspent_output do
    field(:from, :hex)
    field(:amount, :float)
    field(:type, :string)
    field(:nft_address, :hex)
  end

  @desc """
  [TransactionInput] represents the inputs from the transaction
  It includes:
  - From: transaction which send the amount of assets
  - Amount: asset amount
  - Type: UCO/NFT/Call
  - NFT address: address of the NFT if the type is NFT
  - Spent: determines if the input has been spent
  - Timestamp: Date time when the inputs was generated
  """
  object :transaction_input do
    field(:from, :hex)
    field(:amount, :float)
    field(:type, :string)
    field(:nft_address, :hex)
    field(:spent, :boolean)
    field(:timestamp, :timestamp)
  end

  @desc """
  [TransactionMovement] represents ledger transaction movement
  It includes:
  - TO: asset transfer recipient
  - Amount: asset amount
  - Type: UCO/NFT
  - NFT address: address of the NFT if the type is NFT
  """
  object :transaction_movement do
    field(:to, :hex)
    field(:amount, :float)
    field(:type, :string)
    field(:nft_address, :hex)
  end

  @desc """
  [NodeMovement] represents node transaction movement
  It includes:
  - To: node public key
  - Amount: reward (UCO)
  """
  object :node_movement do
    field(:to, :hex)
    field(:amount, :float)
  end

  @desc """
  [CrossValidationStamp] represents the approval of the validation stamp by a cross validation node.
  It includes:
  - Signature: signature of the validation stamp
  - Node: node public key
  """
  object :cross_validation_stamp do
    field(:signature, :hex)
    field(:node, :hex)
  end

  @desc """
  [Balance] represents a ledger balance.
  It includes:
  - UCO: uco balance
  - NFT: NFT balances
  """
  object :balance do
    field(:uco, :float)
    field(:nft, list_of(:nft_balance))
  end

  @desc """
  [NftBalance] represents a NFT ledger balance.
  It includes:
  - NFT: address of the NFT
  - Amount: amount of NFT
  """
  object :nft_balance do
    field(:address, :hex)
    field(:amount, :float)
  end
end
