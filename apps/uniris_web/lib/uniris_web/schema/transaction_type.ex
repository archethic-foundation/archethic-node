defmodule UnirisWeb.Schema.TransactionType do
  @moduledoc false

  use Absinthe.Schema.Notation

  import_types(UnirisWeb.Schema.CryptoTypes)

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
  end

  @desc "[Transaction] represents a unitary transaction in the Uniris network."
  object :transaction do
    field(:address, :hash)
    field(:timestamp, :integer)
    field(:type, :transaction_type)
    field(:data, :transaction_data)
    field(:previous_public_key, :public_key)
    field(:previous_signature, :signature)
    field(:origin_signature, :signature)
    field(:validation_stamp, :validation_stamp)
    field(:cross_validation_stamps, list_of(:cross_validation_stamp))
  end

  object :transaction_data do
    field(:ledger, :transaction_ledger)
    field(:contract, :string)
    field(:content, :string)
    field(:keys, :transaction_secret_keys)
  end

  input_object :transaction_data_input do
    field(:ledger, :transaction_ledger_input)
    field(:contract, :string)
    field(:content, :string)
    field(:keys, :transaction_secret_keys_input)
  end

  object :transaction_ledger do
    field(:uco, :uco_ledger)
  end

  input_object :transaction_ledger_input do
    field(:uco, :uco_ledger_input)
  end

  object :transfer do
    field(:to, :hash)
    field(:amount, :float)
  end

  input_object :transfer_input do
    field(:to, :hash)
    field(:amount, :float)
  end

  object :uco_ledger do
    field(:transfers, list_of(:transfer))
  end

  input_object :uco_ledger_input do
    field(:transfers, list_of(:transfer_input))
  end

  object :transaction_secret_keys do
    field(:secret, :cipher)
    field(:authorized_keys, list_of(:transaction_authorized_key))
  end

  input_object :transaction_secret_keys_input do
    field(:secret, :cipher)
    field(:authorized_keys, list_of(:transaction_authorized_key_input))
  end

  object :transaction_authorized_key do
    field(:public_key, :public_key)
    field(:encrypted_key, :cipher)
  end

  input_object :transaction_authorized_key_input do
    field(:public_key, :public_key)
    field(:encrypted_key, :cipher)
  end

  object :validation_stamp do
    field(:proof_of_work, :public_key)
    field(:proof_of_integrity, :hash)
    field(:ledger_movements, :ledger_movements)
    field(:node_movements, :node_movements)
    field(:signature, :signature)
  end

  object :ledger_movements do
    field(:uco, :utxo)
  end

  object :utxo do
    field(:previous, :previous_utxo)
    field(:next, :float)
  end

  object :previous_utxo do
    field(:from, list_of(:public_key))
    field(:amount, :float)
  end

  object :node_movements do
    field(:fee, :float)
    field(:rewards, list_of(:node_reward))
  end

  object :node_reward do
    field(:node, :public_key)
    field(:amount, :float)
  end

  object :cross_validation_stamp do
    field(:signature, :signature)
    field(:inconsistencies, list_of(:string))
    field(:node, :public_key)
  end
end
