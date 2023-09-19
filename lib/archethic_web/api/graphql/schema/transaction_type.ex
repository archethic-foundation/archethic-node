defmodule ArchethicWeb.API.GraphQL.Schema.TransactionType do
  @moduledoc false

  use Absinthe.Schema.Notation

  alias ArchethicWeb.API.GraphQL.Schema.Resolver

  alias Archethic.TransactionChain.Transaction

  @desc "[Transaction] represents a unitary transaction in the Archethic network."
  object :transaction do
    field(:version, :integer)
    field(:address, :address)
    field(:type, :string)
    field(:data, :data)
    field(:previous_public_key, :public_key)
    field(:previous_signature, :hex)
    field(:previous_address, :address)
    field(:origin_signature, :hex)
    field(:validation_stamp, :validation_stamp)
    field(:cross_validation_stamps, list_of(:cross_validation_stamp))

    field :inputs, list_of(:transaction_input) do
      arg(:paging_offset, :non_neg_integer)
      arg(:limit, :pos_integer)

      resolve(fn args, %{source: %{address: address}} ->
        paging_offset = Map.get(args, :paging_offset, 0)
        limit = Map.get(args, :limit, 0)
        Resolver.get_inputs(address, paging_offset, limit)
      end)
    end

    field :chain_length, :integer do
      resolve(fn _, %{source: %{address: address}} ->
        Resolver.get_chain_length(address)
      end)
    end

    field :balance, :balance do
      resolve(fn _, %{source: %{address: address}} ->
        Resolver.get_balance(address)
      end)
    end
  end

  @desc """
  [TransactionData] represents the data section for every transaction.
  It includes:
  - Ledger: asset transfers
  - Code: smart contract code (hexadecimal),
  - Content: free zone for data hosting (string or hexadecimal)
  - Ownership: authorization/delegations containing list of secrets and their authorized public keys to proof the ownership
  - Recipients: For non asset transfers, the list of recipients of the transaction (e.g Smart contract interactions)
  """
  object :data do
    field(:ledger, :ledger)
    field(:code, :string)
    field(:content, :content)
    field(:ownerships, list_of(:ownership))
    field(:recipients, list_of(:address))
    field(:action_recipients, list_of(:recipient))
  end

  @desc "[Ledger] represents the ledger operations to perform"
  object :ledger do
    field(:uco, :uco_ledger)
    field(:token, :token_ledger)
  end

  @desc "[UCOTransfer] represents the an asset transfer"
  object :uco_transfer do
    field(:to, :address)
    field(:amount, :integer)
  end

  @desc "[TokenTransfer] represents the an asset transfer"
  object :token_transfer do
    field(:to, :address)
    field(:amount, :integer)
    field(:token_address, :address)
    field(:token_id, :integer)
  end

  @desc "[UCOLedger] represents the transfers to perform on the UCO ledger"
  object :uco_ledger do
    field(:transfers, list_of(:uco_transfer))
  end

  @desc "[TokenLedger] represents the transfers to perform on the UCO ledger"
  object :token_ledger do
    field(:transfers, list_of(:token_transfer))
  end

  @desc "[Ownership] represents a block to set a secret and the authorized public keys able to decrypt the secret"
  object :ownership do
    field(:secret, :hex)

    field(:authorized_public_keys, list_of(:authorized_key)) do
      resolve(fn _, %{source: %{authorized_keys: authorized_keys}} ->
        formatted_authorized_keys =
          Enum.map(authorized_keys, fn {public_key, encrypted_secret_key} ->
            %{public_key: public_key, encrypted_secret_key: encrypted_secret_key}
          end)

        {:ok, formatted_authorized_keys}
      end)
    end
  end

  @desc "[Recipient] represents a Smart Contract call"
  object :recipient do
    field(:address, :hex)
    field(:action, :string)
    field(:args, :recipient_args)
  end

  @desc "[Recipient Args] represents the args of a named action call"
  scalar :recipient_args do
    serialize(& &1)
  end

  @desc """
  [AuthorizedKey] represents a authorized public key with the encrypted secret key for this given key.
  By decrypting this secret key, the authorized public key will be able to decrypt its related secret
  """
  object :authorized_key do
    field(:public_key, :public_key)
    field(:encrypted_secret_key, :hex)
  end

  @desc """
  [ValidationStamp] represents the validation performs by the coordinator
  It includes:
  - Proof of work: Public key matching the origin signature
  - Proof of integrity: Hash of the previous proof of integrity and the transaction
  - Ledger operations: All the operations performed by the transaction
  - Signature: Coordinator signature of the stamp
  - Protocol version: Version of the transaction validation protocol
  """
  object :validation_stamp do
    field(:timestamp, :timestamp)
    field(:proof_of_work, :public_key)
    field(:proof_of_integrity, :hash)
    field(:ledger_operations, :ledger_operations)
    field(:signature, :hex)
    field(:protocol_version, :integer)
  end

  @desc """
  [LedgerOperations] represents the ledger operations performed by the transaction
  It includes:
  - Transaction movements: assets transfers
  - Unspent outputs: remaining unspent outputs
  - Fee: transaction fee
  """
  object :ledger_operations do
    field(:transaction_movements, list_of(:transaction_movement))
    field(:unspent_outputs, list_of(:unspent_output))
    field(:consumed_inputs, list_of(:unspent_output))
    field(:fee, :integer)
  end

  @desc """
  [UnspentOutput] represents the remaining unspent output of the transaction.
  It includes:
  - From: transaction which send the amount of assets
  - Amount: asset amount
  - Type: UCO/token
  - token address: address of the token if the type is token
  - token id: It is the id for a token which is allocated when the token is minted.
  - Timestamp: Date time when the UTXO created/manipulated
  - Version: Version of the UTXO data structure
  - State: It is the state of a smart contract
  """
  object :unspent_output do
    field(:from, :address)
    field(:amount, :integer)
    field(:type, :string)
    field(:token_address, :address)
    field(:token_id, :integer)
    field(:timestamp, :timestamp)
    field(:version, :integer)
    field(:state, :state)
  end

  @desc """
    [State] represents the smart contract state
  """
  scalar :state do
    serialize(& &1)
  end

  @desc """
  [TransactionInput] represents the inputs from the transaction
  It includes:
  - From: transaction which send the amount of assets
  - Amount: asset amount
  - Type: UCO/token/Call
  - token address: address of the token if the type is token
  - Spent: determines if the input has been spent
  - Timestamp: Date time when the inputs was generated
  - token id: It is the id for a token which is allocated when the token is minted.
  """
  object :transaction_input do
    field(:from, :address)
    field(:amount, :integer)
    field(:type, :string)
    field(:token_address, :address)
    field(:spent, :boolean)
    field(:timestamp, :timestamp)
    field(:token_id, :integer)
  end

  @desc """
  [TransactionMovement] represents ledger transaction movement
  It includes:
  - TO: asset transfer recipient
  - Amount: asset amount
  - Type: UCO/token
  - token address: address of the token if the type is token
  - token id: It is the id for a token which is allocated when the token is minted.
  """
  object :transaction_movement do
    field(:to, :address)
    field(:amount, :integer)
    field(:type, :string)
    field(:token_address, :address)
    field(:token_id, :integer)
  end

  @desc """
  [CrossValidationStamp] represents the approval of the validation stamp by a cross validation node.
  It includes:
  - Signature: signature of the validation stamp
  - Node public key: cross validation node's public key
  """
  object :cross_validation_stamp do
    field(:signature, :hex)
    field(:node_public_key, :public_key)
  end

  @desc """
  [Balance] represents a ledger balance.
  It includes:
  - UCO: uco balance
  - token: token balances
  """
  object :balance do
    field(:uco, :integer)
    field(:token, list_of(:token_balance))
  end

  @desc """
  [token] represents a token metadata.
  It includes:
  - genesis: Genesis address to the token
  - name: Name of the token
  - symbol: Symbol of the token
  - supply: Supply of the token
  - type: Type of the token
  - decimals: Number of decimals of the token
  - properties: Properties of the token (if any)
  - collection: List of properties for a collection (if any)
  - ownerships: authorization/delegations containing list of secrets and their authorized public keys to proof the ownership
  - id: Unique identification of the token on the chain
  """
  object :token do
    field(:genesis, :address)
    field(:name, :string)
    field(:symbol, :string)
    field(:supply, :integer)
    field(:type, :string)
    field(:properties, :token_properties)
    field(:collection, list_of(:token_properties))
    field(:ownerships, list_of(:ownership))
    field(:decimals, :integer)
    field(:id, :string)
  end

  @desc """
    [tokenProperties] represents a token's properties
  """
  scalar :token_properties do
    serialize(& &1)
  end

  @desc """
  [tokenBalance] represents a token ledger balance.
  It includes:
  - Token: address of the token
  - Amount: amount of token
  - Token ID: ID of the token
  """
  object :token_balance do
    field(:address, :address)
    field(:amount, :integer)
    field(:token_id, :integer)
  end

  @desc """
  The [TransactionType] scalar type represents a transaction type
  """
  scalar :transaction_type do
    serialize(&Atom.to_string/1)
    parse(&parse_type/1)
  end

  @spec parse_type(Absinthe.Blueprint.Input.String.t()) ::
          {:ok, Transaction.transaction_type()} | :error
  defp parse_type(%Absinthe.Blueprint.Input.String{value: tx_type}) do
    transaction_types =
      Transaction.types()
      |> Enum.map(&{Atom.to_string(&1), &1})
      |> Enum.into(%{})

    case Map.get(transaction_types, tx_type) do
      nil ->
        :error

      tx_type ->
        {:ok, tx_type}
    end
  end

  defp parse_type(_), do: :error
end
