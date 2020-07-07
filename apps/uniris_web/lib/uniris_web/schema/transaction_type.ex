defmodule UnirisWeb.Schema.TransactionType do
  @moduledoc false

  use Absinthe.Schema.Notation

  import_types(UnirisWeb.Schema.CryptoTypes)
  import_types(UnirisWeb.Schema.DateTimeType)
  import_types(UnirisWeb.Schema.HexType)

  @desc """
  The [TransactionType] enum represents the type of Uniris transactions.
  Types can affect behaviour in term of replication or storage, such as network transaction (node, node_shared_secrets, beacon).
  """
  enum :transaction_type do
    value(:transfer, as: :transfer)
    value(:identity, as: :identity)
    value(:keychain, as: :keychain)
    value(:node, as: :node)
    value(:node_shared_secrets, as: :node_shared_secrets)
    value(:origin_shared_secrets, as: :origin_shared_secrets)
    value(:beacon, as: :beacon)
    value(:hosting, as: :hosting)
  end

  @desc "[Transaction] represents a unitary transaction in the Uniris network."
  object :transaction do
    field(:address, :hash)
    field(:timestamp, :timestamp)
    field(:type, :transaction_type)
    field(:data, :data)
    field(:previous_public_key, :public_key)
    field(:previous_signature, :hex)
    field(:origin_signature, :hex)
    field(:validation_stamp, :validation_stamp)
    field(:cross_validation_stamps, list_of(:cross_validation_stamp))

    field :inputs, list_of(:unspent_output) do
      resolve(fn _, %{source: %{previous_public_key: previous_public_key}} ->
        {:ok, UnirisCore.get_transaction_inputs(previous_public_key)}
      end)
    end

    field :balance, :float do
      resolve(fn _, %{source: %{address: address}} ->
        {:ok, UnirisCore.get_balance(address)}
      end)
    end

    field :chain_length, :integer do
      resolve(fn _, %{ source: %{ address: address}} ->
        {:ok, UnirisCore.get_transaction_chain_length(address)}
      end)
    end

    field :previous_transaction, :transaction do
      resolve(fn _, %{ source: %{ previous_public_key: previous_public_key}} ->
        previous_address = UnirisCore.Crypto.hash(previous_public_key)
        UnirisCore.search_transaction(previous_address)
      end)
    end
  end

  @desc """
  [TransactionData] represents the data section for every transaction.
  It includes:
  - Ledger: asset transfers
  - Code: smart contract code (hexadecimal),
  - Content: free zone for data hosting (hexadecimal)
  - Keys: Secrets and authorized public keys to decrypt the secret
  - Recipients: For non asset transfers, the list of recipients of the transaction (e.g Smart contract interactions)
  """
  object :data do
    field(:ledger, :ledger)
    field(:code, :string)
    field(:content, :string)
    field(:keys, :keys)
    field(:recipients, list_of(:hash))
  end

  input_object :data_input do
    field(:ledger, :ledger_input)
    field(:code, :hex)
    field(:content, :hex)
    field(:keys, :keys_input)
    field(:recipients, list_of(:hash))
  end

  @desc "[Ledger] represents the ledger operations to perform"
  object :ledger do
    field(:uco, :uco_ledger)
  end

  input_object :ledger_input do
    field(:uco, :uco_ledger_input)
  end

  @desc "[Transfer] represents the an asset transfer"
  object :transfer do
    field(:to, :hash)
    field(:amount, :float)
  end

  input_object :transfer_input do
    field(:to, :hash)
    field(:amount, :float)
  end

  @desc "[UCOLedger] represents the transfers to perform on the UCO ledger"
  object :uco_ledger do
    field(:transfers, list_of(:transfer))
  end

  input_object :uco_ledger_input do
    field(:transfers, list_of(:transfer_input))
  end

  @desc "[Keys] represents a block to set secret and authorized public keys able to read the secret"
  object :keys do
    field(:secret, :hex)
    field(:authorized_keys, list_of(:authorized_key))
  end

  input_object :keys_input do
    field(:secret, :hex)
    field(:authorized_keys, list_of(:authorized_key_input))
  end

  @desc """
  [AuthorizedKey] represents list of public keys with the encrypted secret for this given key.
  By decrypting this secret keys, the authorized public keys will be able to decrypt the secret
  """
  object :authorized_key do
    field(:public_key, :public_key)
    field(:encrypted_key, :hex)
  end

  input_object :authorized_key_input do
    field(:public_key, :public_key)
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
    field(:proof_of_work, :public_key)
    field(:proof_of_integrity, :hash)
    field(:ledger_operations, :ledger_operations)
    field(:signature, :hex)
  end

  @desc """
  [LedgerOperations] represents the ledger operations performed by the transaction
  It includes:
  - Transaction movements: assets transfers
  - Node movements: node rewards
  - Unspent outputs: remaing unspent outputs
  - Fee: transaction fee (distributed over the node rewards)
  """
  object :ledger_operations do
    field(:transaction_movements, list_of(:movement))
    field(:node_movements, list_of(:movement))
    field(:unspent_outputs, list_of(:unspent_output))
    field(:fee, :float)
  end

  @desc "[UnspentOutput] represents the remaining unspent output of the transaction"
  object :unspent_output do
    field(:from, :hash)
    field(:amount, :float)
  end

  @desc "[Movement] represents ledger movements from the transaction "
  object :movement do
    field(:to, :hash)
    field(:amount, :float)
  end

  @desc "[CrossValidationStamp] represents the approval of the validation stamp by a cross validation node"
  object :cross_validation_stamp do
    field(:signature, :hex)
    field(:node, :public_key)
  end
end
