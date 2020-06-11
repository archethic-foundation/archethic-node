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
    value(:hosting, as: :hosting)
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
  end

  object :transaction_data do
    field(:ledger, :transaction_ledger)
    field(:code, :string)
    field(:content, :string)
    field(:keys, :transaction_secret_keys)
  end

  input_object :transaction_data_input do
    field(:ledger, :transaction_ledger_input)
    field(:code, :string)
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
    field(:ledger_operations, :ledger_operations)
    field(:signature, :signature)
  end

  object :ledger_operations do
    field(:transaction_movements, list_of(:movement))
    field(:node_movements, list_of(:movement))
    field(:unspent_outputs, list_of(:unspent_output))
    field(:fee, :float)
  end

  object :unspent_output do
    field(:from, :hash)
    field(:amount, :float)
  end

  object :movement do
    field(:to, :hash)
    field(:amount, :float)
  end

  object :cross_validation_stamp do
    field(:signature, :signature)
    field(:node, :public_key)
  end
end
