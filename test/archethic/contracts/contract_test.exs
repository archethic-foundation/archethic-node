defmodule Archethic.Contracts.ContractTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.ContractFactory
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Interpreter
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

  describe "from_transaction/1" do
    test "should return Contract with contract_tx filled" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      {:ok, contract_with_code} = Interpreter.parse(code)

      expected_contract = %Contract{
        contract_with_code
        | transaction: contract_tx,
          state: State.empty()
      }

      ^expected_contract = Contract.from_transaction!(contract_tx)
    end

    test "should return Contract with state filled" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      state = %{"key" => "value"}
      contract_tx = ContractFactory.create_valid_contract_tx(code, state: State.serialize(state))

      {:ok, contract_with_code} = Interpreter.parse(code)
      expected_contract = %Contract{contract_with_code | transaction: contract_tx, state: state}

      ^expected_contract = Contract.from_transaction!(contract_tx)
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

      {:ok, %ActionWithTransaction{next_tx: next_tx}} =
        Contracts.execute_trigger(
          {:datetime, DateTime.from_unix!(trigger_time)},
          contract,
          nil,
          nil,
          []
        )

      assert {:ok,
              signed_tx = %Transaction{previous_public_key: ^pub, previous_signature: signature}} =
               Contracts.sign_next_transaction(contract, next_tx, 1)

      tx_payload =
        Transaction.extract_for_previous_signature(signed_tx) |> Transaction.serialize(:extended)

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

      assert {:ok, %ActionWithTransaction{next_tx: next_tx}} =
               Contracts.execute_trigger(
                 {:datetime, DateTime.from_unix!(trigger_time)},
                 contract,
                 nil,
                 nil,
                 []
               )

      assert %Transaction{data: %TransactionData{ownerships: []}} = next_tx

      assert {:ok, %Transaction{data: %TransactionData{ownerships: [new_ownership]}}} =
               Contracts.sign_next_transaction(contract, next_tx, 1)

      assert new_ownership != ownerships
      assert Ownership.authorized_public_key?(new_ownership, storage_nonce_public_key)
    end
  end

  describe "contains_trigger?/1" do
    test "should return true if contract contains trigger" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("Didn't find something funny")
        end
      """

      assert code
             |> ContractFactory.create_valid_contract_tx()
             |> Contract.from_transaction!()
             |> Contract.contains_trigger?()

      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("Didn't find something funny")
        end

        actions triggered_by: datetime, at: 1676332800 do
          Contract.set_content("Incredibly usefull action")
        end
      """

      assert code
             |> ContractFactory.create_valid_contract_tx()
             |> Contract.from_transaction!()
             |> Contract.contains_trigger?()
    end

    test "should return false if contract does not contains trigger" do
      code = """
        @version 1
        condition inherit: []
      """

      refute code
             |> ContractFactory.create_valid_contract_tx()
             |> Contract.from_transaction!()
             |> Contract.contains_trigger?()
    end

    test "should return false if contract contains empty trigger" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
        end
      """

      refute code
             |> ContractFactory.create_valid_contract_tx()
             |> Contract.from_transaction!()
             |> Contract.contains_trigger?()
    end
  end
end
