defmodule Archethic.Contracts.Interpreter.Library.Common.CryptoTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.State
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  doctest Crypto

  # ----------------------------------------
  describe "hash/1" do
    test "should work without algo" do
      text = "wu-tang"
      assert Crypto.hash(text) == Base.encode16(:crypto.hash(:sha256, text))
    end
  end

  describe "hash/2" do
    test "should work with algo" do
      text = "wu-tang"
      assert Crypto.hash(text, "sha512") == Base.encode16(:crypto.hash(:sha512, text))
    end

    test "should work with keccak256 for clear text" do
      text = "wu-tang"

      # Here directly use string to ensure ExKeccak dependency still works
      expected_hash = "CBB3D06AFFDADC9F6B5949E13AA7B06303731811452F61C6F3851F325CBE9D3E"

      assert ExKeccak.hash_256(text) |> Base.encode16() == expected_hash
      assert Crypto.hash(text, "keccak256") == expected_hash
    end

    test "should work with keccak256 for hexadecimal text" do
      hash = :crypto.hash(:sha256, "wu-tang")

      expected_hash = ExKeccak.hash_256(hash) |> Base.encode16()

      hex_hash = Base.encode16(hash)

      assert Crypto.hash(hex_hash, "keccak256") == expected_hash
    end
  end

  describe "sign_with_recovery/1" do
    test "should retrieve seed from scope and sign hash" do
      code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        hash = Crypto.hash(transaction.content, "sha256")
        sig = Crypto.sign_with_recovery(hash)
        Contract.set_content Json.to_string(sig)
      end
      """

      contract = ContractFactory.create_valid_contract_tx(code) |> Contract.from_transaction!()

      trigger_tx = TransactionFactory.create_valid_transaction([], content: "I'll be signed !")

      assert {:ok, %Transaction{data: %TransactionData{content: content}}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 contract,
                 State.empty(),
                 trigger_tx,
                 nil
               )

      assert {:ok, sig} = Jason.decode(content)

      assert %{
               "r" => "BCAA43A2972A94FE42F4989EBB826B3F9BDC841623E22C7E7F8602D06C15B99E",
               "s" => "1017847D5B93517FA802CC3CA07D66DBABC72D3BAEEFC416D1351345AD007290",
               "v" => 0
             } = sig
    end

    test "should raise an error if contract seed is not set" do
      hash = :crypto.strong_rand_bytes(32) |> Base.encode16()
      assert_raise Library.Error, fn -> Crypto.sign_with_recovery(hash) end
    end

    test "should raise an error if hash is not valid" do
      hash = "invalid"
      assert_raise Library.Error, fn -> Crypto.sign_with_recovery(hash) end
    end
  end

  describe "hmac/3" do
    test "should create hmac with default key" do
      code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        Contract.set_content Crypto.hmac(transaction.content)
      end
      """

      contract = ContractFactory.create_valid_contract_tx(code) |> Contract.from_transaction!()

      trigger_tx = TransactionFactory.create_valid_transaction([], content: "I'll be hmacked !")

      assert {:ok, %Transaction{data: %TransactionData{content: content}}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 contract,
                 State.empty(),
                 trigger_tx,
                 nil
               )

      assert "E82E28E72D4C0436AB7443969B82B0F5E9F6B796BC354E42A1B22E70D9EE5BBA" == content
    end

    test "should create hmac with specified algo" do
      code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        Contract.set_content Crypto.hmac(transaction.content, "sha512")
      end
      """

      contract = ContractFactory.create_valid_contract_tx(code) |> Contract.from_transaction!()

      trigger_tx = TransactionFactory.create_valid_transaction([], content: "I'll be hmacked !")

      assert {:ok, %Transaction{data: %TransactionData{content: content}}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 contract,
                 State.empty(),
                 trigger_tx,
                 nil
               )

      assert "3A2EF5397A8F062432EE759457169D2E0950A8A5C03FCB320CF0C2C4141159CA13CC2F6E696B07F0176A0069E51E4C35BF55C4665E31241F495F596DA7968172" ==
               content
    end

    test "should create hmac with specified key" do
      assert "50116EBE56205D9CC19043FF705A4341A68125FE4B5DA32F09195929B5A5EEA1" ==
               Crypto.hmac("I'll be hmacked !", "sha256", "key")
    end

    test "should raise an error if contract seed is not set" do
      assert_raise Library.Error, fn -> Crypto.hmac("data") end
    end

    test "should raise an error if algo is invalid" do
      assert_raise Library.Error, fn -> Crypto.hmac("data", "invalid", "key") end
    end
  end
end
