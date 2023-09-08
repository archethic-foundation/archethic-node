defmodule Archethic.ContractFactory do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.TransactionFactory

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

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
    seed = Keyword.get(opts, :seed, "seed")
    ownerships = Keyword.get(opts, :ownerships, nil)

    ownerships =
      if ownerships do
        ownerships
      else
        aes_key = :crypto.strong_rand_bytes(32)
        secret = Crypto.aes_encrypt(seed, aes_key)
        storage_nonce_pub_key = Crypto.storage_nonce_public_key()
        encrypted_key = Crypto.ec_encrypt(aes_key, storage_nonce_pub_key)

        [%Ownership{secret: secret, authorized_keys: %{storage_nonce_pub_key => encrypted_key}}]
      end

    opts =
      Keyword.update(opts, :type, :contract, & &1)
      |> Keyword.put(:ownerships, ownerships)
      |> Keyword.put(:code, code)

    TransactionFactory.create_valid_transaction([], opts)
  end

  def create_next_contract_tx(
        %Transaction{data: %TransactionData{ownerships: ownerships, code: code}},
        opts \\ []
      ) do
    opts = Keyword.update(opts, :ownerships, ownerships, & &1) |> Keyword.update(:index, 1, & &1)

    create_valid_contract_tx(code, opts)
  end

  def append_contract_constant(constants, code, content \\ "") do
    if Map.has_key?(constants, "contract") do
      constants
    else
      Map.put(
        constants,
        "contract",
        Constants.from_transaction(
          TransactionFactory.create_valid_transaction([],
            type: :contract,
            code: code,
            content: content
          )
        )
      )
    end
  end
end
