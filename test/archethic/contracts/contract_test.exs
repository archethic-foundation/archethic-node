defmodule Archethic.Contracts.ContractTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  alias Archethic.Contracts.Contract

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ownership

  describe "get_trigger_for_recipient/2" do
    test "should return trigger" do
      assert {:transaction, "vote", 1} =
               Contract.get_trigger_for_recipient(%Recipient{
                 address: random_address(),
                 action: "vote",
                 args: ["Julio"]
               })
    end

    test "should return {:transaction, nil, nil} when no action nor args" do
      assert {:transaction, nil, nil} ==
               Contract.get_trigger_for_recipient(%Recipient{address: random_address()})
    end
  end

  describe "from_transaction" do
    test "should create a contract with contract seed" do
      code = """
        @version 1

        condition transaction: []

        actions triggered_by: transaction do
          Contract.set_content "ok"
        end
      """

      storage_nonce = Crypto.storage_nonce_public_key()

      contract_tx =
        %Transaction{data: %TransactionData{ownerships: ownerships}} =
        ContractFactory.create_valid_contract_tx(code)

      ownership =
        %Ownership{secret: encrypted_seed} =
        Enum.find(ownerships, &Ownership.authorized_public_key?(&1, storage_nonce))

      encrypted_key = Ownership.get_encrypted_key(ownership, storage_nonce)

      assert {:ok, %Contract{seed: {^encrypted_seed, ^encrypted_key}}} =
               Contract.from_transaction(contract_tx)
    end

    test "should not add seed to contract if it does not exists" do
      code = """
        @version 1

        condition transaction: []
      """

      contract_tx = TransactionFactory.create_valid_transaction([], code: code)

      assert {:ok, %Contract{seed: nil}} = Contract.from_transaction(contract_tx)
    end
  end
end
