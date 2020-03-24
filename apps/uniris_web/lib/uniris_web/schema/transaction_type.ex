defmodule UnirisWeb.Schema.TransactionType do
  @moduledoc false

  use Absinthe.Schema.Notation

  import_types UnirisWeb.Schema.CryptoTypes

  @desc """
  The [TransactionType] enum represents the type of Uniris transactions.
  Types can affect behaviour in term of replication or storage, such as network transaction (node, node_shared_secrets, beacon).
  """
  enum :transaction_type do
    value :transfer, as: :transfer
    value :identity, as: :identity
    value :keychain, as: :keychain
    value :node, as: :node
    value :node_shared_secrets, as: :node_shared_secrets
    value :beacon, as: :beacon
  end

  @desc "[Transaction] represents a unitary transaction in the Uniris network."
  object :transaction do
    field(:address, :hash)
    field(:timestamp, :integer)
    field(:type, :transaction_type)
    field(:data,  :transaction_data)
    field(:previous_public_key, :public_key)
    field(:previous_signature, :signature)
    field(:origin_signature, :signature)
  end

  object :transaction_data do
    field(:ledger, :transaction_ledger)
    field(:contract, :string)
    field(:content, :string)
    field(:keys, :transaction_secret_keys)
  end

  object :transaction_ledger do
    field(:uco, :uco_ledger)
  end

  object :transfer do
    field(:to, :hash)
    field(:amount, :float)
  end

  object :uco_ledger do
    field(:transfers, list_of(:transfer))
  end

  object :transaction_secret_keys do
    field(:secret, :cipher)
    field(:authorized_keys, list_of(:transaction_authorized_key))
  end

  object :transaction_authorized_key do
    field(:public_key, :public_key)
    field(:encrypted_key, :cipher)
  end

end
