defmodule Archethic.Contracts.ContractTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts
  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient

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

  describe "sign_next_transaction/3" do
    test "should sign next_transaction using contract seed" do
      trigger_time = 1_676_332_800

      code = """
      @version 1
      actions triggered_by: datetime, at: #{trigger_time} do
        Contract.set_content "ok"
      end
      """

      seed = "contract_seed"
      {pub, _priv} = Crypto.derive_keypair(seed, 1)

      contract =
        code
        |> ContractFactory.create_valid_contract_tx(seed: seed)
        |> Contract.from_transaction!()

      %Contract.Result.Success{next_tx: next_tx} =
        Contracts.execute_trigger(
          {:datetime, DateTime.from_unix!(trigger_time)},
          contract,
          nil,
          nil,
          nil
        )

      assert {:ok,
              signed_tx = %Transaction{previous_public_key: ^pub, previous_signature: signature}} =
               Contract.sign_next_transaction(contract, next_tx, 1)

      tx_payload =
        Transaction.extract_for_previous_signature(signed_tx) |> Transaction.serialize()

      assert Crypto.verify?(signature, tx_payload, pub)
    end

    test "should add contract seed ownership in next tx" do
      trigger_time = 1_676_332_800

      code = """
      @version 1
      actions triggered_by: datetime, at: #{trigger_time} do
        Contract.set_content "ok"
      end
      """

      contract_tx =
        %Transaction{data: %TransactionData{ownerships: ownerships}} =
        ContractFactory.create_valid_contract_tx(code)

      contract = Contract.from_transaction!(contract_tx)

      storage_nonce_public_key = Crypto.storage_nonce_public_key()

      assert %Contract.Result.Success{next_tx: next_tx} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(trigger_time)},
                 contract,
                 nil,
                 nil,
                 nil
               )

      assert %Transaction{data: %TransactionData{ownerships: []}} = next_tx

      assert {:ok, %Transaction{data: %TransactionData{ownerships: [new_ownership]}}} =
               Contract.sign_next_transaction(contract, next_tx, 1)

      assert new_ownership != ownerships
      assert Ownership.authorized_public_key?(new_ownership, storage_nonce_public_key)
    end
  end
end
