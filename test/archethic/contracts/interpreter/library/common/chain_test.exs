defmodule Archethic.Contracts.Interpreter.Library.Common.ChainTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Chain

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.P2P.Message.GetFirstPublicKey
  alias Archethic.P2P.Message.GetFirstTransactionAddress
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.TransactionFactory

  import Mox

  doctest Chain

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })
  end

  # ----------------------------------------
  describe "get_genesis_address/1" do
    test "should work" do
      tx_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      genesis_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Chain.get_genesis_address("#{Base.encode16(tx_address)}")
      end
      """

      MockClient
      |> expect(:send_message, fn
        _, %GetGenesisAddress{address: ^tx_address}, _ ->
          {:ok, %GenesisAddress{address: genesis_address, timestamp: DateTime.utc_now()}}
      end)

      assert %Transaction{data: %TransactionData{content: content}} = sanitize_parse_execute(code)
      assert content == Base.encode16(genesis_address)
    end
  end

  # ----------------------------------------
  describe "get_first_transaction_address/1" do
    test "should work when there is a first transaction" do
      tx_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      first_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Chain.get_first_transaction_address("#{Base.encode16(tx_address)}")
      end
      """

      MockClient
      |> expect(:send_message, fn
        _, %GetFirstTransactionAddress{address: ^tx_address}, _ ->
          {:ok, %FirstTransactionAddress{address: first_address, timestamp: DateTime.utc_now()}}
      end)

      assert %Transaction{data: %TransactionData{content: content}} = sanitize_parse_execute(code)
      assert content == Base.encode16(first_address)
    end

    test "should return nil if there are no transaction" do
      tx_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        if Chain.get_first_transaction_address("#{Base.encode16(tx_address)}") == nil do
          Contract.set_content "ok"
        end
      end
      """

      MockClient
      |> expect(:send_message, fn
        _, %GetFirstTransactionAddress{address: ^tx_address}, _ ->
          {:ok, %NotFound{}}
      end)

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "get_genesis_public_key/1" do
    test "should work" do
      {genesis_pub_key, _} = Crypto.generate_deterministic_keypair("seed")
      {pub_key, _} = Crypto.derive_keypair("seed", 19)

      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Chain.get_genesis_public_key("#{Base.encode16(pub_key)}")
      end
      """

      MockClient
      |> expect(:send_message, fn
        _, %GetFirstPublicKey{public_key: ^pub_key}, _ ->
          {:ok, %FirstPublicKey{public_key: genesis_pub_key}}
      end)

      assert %Transaction{data: %TransactionData{content: content}} = sanitize_parse_execute(code)
      assert content == Base.encode16(genesis_pub_key)
    end

    test "should return nil if the key does not exist" do
      {pub_key, _} = Crypto.derive_keypair("seed", 19)

      code = ~s"""
      actions triggered_by: transaction do
        if Chain.get_genesis_public_key("#{Base.encode16(pub_key)}") == nil do
          Contract.set_content "ok"
        end
      end
      """

      MockClient
      |> expect(:send_message, fn
        _, %GetFirstPublicKey{public_key: ^pub_key}, _ ->
          {:ok, %NotFound{}}
      end)

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  describe "get_transaction/1" do
    test "should return the existing transaction" do
      tx =
        %Transaction{address: address} =
        TransactionFactory.create_valid_transaction([], content: "Gloubi-Boulga")

      MockClient
      |> expect(:send_message, fn
        _, %GetTransaction{address: ^address}, _ -> {:ok, tx}
      end)

      code = ~s"""
      actions triggered_by: transaction do
        tx = Chain.get_transaction("#{Base.encode16(address)}")
        Contract.set_content tx.content
      end
      """

      assert %Transaction{data: %TransactionData{content: content}} = sanitize_parse_execute(code)
      assert content == "Gloubi-Boulga"
    end

    test "should return nil when the transaction does not exist" do
      address = random_address()

      code = ~s"""
      actions triggered_by: transaction do
        if Chain.get_transaction("#{Base.encode16(address)}") == nil do
          Contract.set_content "ok"
        end
      end
      """

      MockClient
      |> expect(:send_message, fn
        _, %GetTransaction{address: ^address}, _ ->
          {:ok, %NotFound{}}
      end)

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  describe "get_burn_address/0" do
    test "should return burn address" do
      assert <<0::16, 0::256>> |> Base.encode16() == Chain.get_burn_address()
    end
  end
end
