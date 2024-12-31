defmodule Archethic.ContractFactory do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Contracts.Interpreter.Constants
  alias Archethic.TransactionFactory

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  import ArchethicCase

  def valid_version1_contract(opts \\ []) do
    code = ~S"""
    condition inherit: [
      content: true
    ]

    condition triggered_by: transaction, as: [
      uco_transfers: Map.size() > 0
    ]

    actions triggered_by: transaction do
      Contract.set_content "hello"
    end
    """

    if Keyword.get(opts, :version_attribute, true) do
      """
      @version 1
      #{code}
      """
    else
      code
    end
  end

  def valid_legacy_contract() do
    ~S"""
    condition inherit: [
      content: true
    ]

    condition transaction: [
      uco_transfers: size() > 0
    ]

    actions triggered_by: transaction do
      set_content "hello"
    end
    """
  end

  def create_valid_contract_tx(code, opts \\ []) do
    opts = Keyword.update(opts, :seed, random_seed(), fn seed -> seed end)
    seed = Keyword.fetch!(opts, :seed)
    ownerships = Keyword.get(opts, :ownerships, [])

    aes_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt(seed, aes_key)
    storage_nonce_pub_key = Crypto.storage_nonce_public_key()
    encrypted_key = Crypto.ec_encrypt(aes_key, storage_nonce_pub_key)

    contract_seed_ownership = %Ownership{
      secret: secret,
      authorized_keys: %{storage_nonce_pub_key => encrypted_key}
    }

    opts =
      Keyword.update(opts, :type, :contract, & &1)
      |> Keyword.put(:ownerships, [contract_seed_ownership | ownerships])
      |> Keyword.put(:code, code)
      |> Keyword.put(:version, 3)

    inputs =
      Keyword.get(opts, :inputs, [
        %UnspentOutput{
          type: :UCO,
          amount: 1_000_000_000,
          from: random_address(),
          timestamp: DateTime.utc_now()
        }
      ])

    TransactionFactory.create_valid_transaction(inputs, opts)
  end

  def create_next_contract_tx(
        prev_tx = %Transaction{
          data: %TransactionData{
            code: code,
            ownerships: [%Ownership{secret: secret, authorized_keys: authorized_keys} | _]
          }
        },
        opts \\ []
      ) do
    opts = opts |> Keyword.update(:index, 1, & &1) |> Keyword.put(:prev_tx, prev_tx)

    storage_nonce_public_key = Crypto.storage_nonce_public_key()
    encrypted_key = Map.get(authorized_keys, storage_nonce_public_key)
    {:ok, aes_key} = Crypto.ec_decrypt_with_storage_nonce(encrypted_key)
    {:ok, seed} = Crypto.aes_decrypt(secret, aes_key)
    opts = Keyword.put(opts, :seed, seed)

    create_valid_contract_tx(code, opts)
  end

  def append_contract_constant(constants, contract_tx) do
    if Map.has_key?(constants, "contract") do
      constants
    else
      Map.put(constants, "contract", Constants.from_contract_transaction(contract_tx))
    end
  end
end
