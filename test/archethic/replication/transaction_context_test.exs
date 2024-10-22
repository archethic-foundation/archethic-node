defmodule Archethic.Replication.TransactionContextTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node
  alias Archethic.Replication.TransactionContext
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionFactory

  import Mox

  describe "fetch_transaction/2" do
    test "should retrieve the transaction" do
      address = random_address()

      MockClient
      |> expect(:send_message, 3, fn _, %GetTransaction{}, _ ->
        {:ok, %Transaction{address: address}}
      end)

      connect_to_n_nodes(5)

      assert %Transaction{} = TransactionContext.fetch_transaction(address)
    end

    test "should ask every node if acceptance_resolver is :accept_transaction" do
      address = random_address()

      MockClient
      |> expect(:send_message, 5, fn _, %GetTransaction{}, _ ->
        # acceptance will fail
        {:ok, %NotFound{}}
      end)

      connect_to_n_nodes(5)

      # no assert, we use expect(5) in the mock
      TransactionContext.fetch_transaction(address, acceptance_resolver: :accept_transaction)
    end
  end

  describe "fetch_genesis_address/2" do
    test "should retrieve the genesis" do
      address = random_address()
      genesis = random_address()

      MockClient
      |> expect(:send_message, 3, fn _, %GetGenesisAddress{}, _ ->
        {:ok, %GenesisAddress{address: genesis, timestamp: DateTime.utc_now()}}
      end)

      connect_to_n_nodes(5)

      assert genesis == TransactionContext.fetch_genesis_address(address)
    end

    test "should ask every node if acceptance_resolver is :accept_different_genesis" do
      address = random_address()

      MockClient
      |> expect(:send_message, 5, fn _, %GetGenesisAddress{}, _ ->
        # acceptance will fail
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      connect_to_n_nodes(5)

      # no assert, we use expect(5) in the mock
      TransactionContext.fetch_genesis_address(address,
        acceptance_resolver: :accept_different_genesis
      )
    end
  end

  describe "stream_transaction_chain/3" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      %{transactions: Enum.map(0..3, &TransactionFactory.create_valid_transaction([], index: &1))}
    end

    test "should retrieve the previous transaction chain with part of chain already stored", %{
      transactions: [tx1, tx2, tx3, tx4]
    } do
      genesis = Transaction.previous_address(tx1)
      addr1 = tx1.address
      addr3 = tx3.address

      MockDB
      |> expect(:get_last_chain_address_stored, fn ^genesis -> addr1 end)

      MockClient
      |> expect(:send_message, fn
        _, %GetTransactionChain{address: ^genesis, paging_state: ^addr1}, _ ->
          {:ok, %TransactionList{transactions: [tx2, tx3, tx4]}}
      end)

      nodes = P2P.authorized_and_available_nodes()

      assert [tx2, tx3] ==
               genesis
               |> TransactionContext.stream_transaction_chain(addr3, nodes)
               |> Enum.to_list()
    end

    test "should retrieve the previous transactions with no tx of the chain already stored", %{
      transactions: [tx1, tx2, tx3, tx4]
    } do
      genesis = Transaction.previous_address(tx1)
      addr3 = tx3.address

      MockDB
      |> expect(:get_last_chain_address_stored, fn ^genesis -> nil end)

      MockClient
      |> expect(:send_message, fn
        _, %GetTransactionChain{address: ^genesis, paging_state: nil}, _ ->
          {:ok, %TransactionList{transactions: [tx1, tx2, tx3, tx4]}}
      end)

      nodes = P2P.authorized_and_available_nodes()

      assert [tx1, tx2, tx3] ==
               genesis
               |> TransactionContext.stream_transaction_chain(addr3, nodes)
               |> Enum.to_list()
    end

    test "should raise en error if part of the chain is not fetched", %{
      transactions: [tx1, tx2, tx3, tx4]
    } do
      genesis = Transaction.previous_address(tx1)
      addr3 = tx3.address

      MockDB
      |> stub(:get_last_chain_address_stored, fn ^genesis -> nil end)

      nodes = P2P.authorized_and_available_nodes()

      # Missing first transaction
      MockClient
      |> expect(:send_message, fn
        _, %GetTransactionChain{address: ^genesis, paging_state: nil}, _ ->
          {:ok, %TransactionList{transactions: [tx2, tx3, tx4]}}
      end)

      expected_message =
        "Replication failed to fetch previous chain after #{Base.encode16(genesis)}"

      assert_raise RuntimeError, expected_message, fn ->
        genesis
        |> TransactionContext.stream_transaction_chain(addr3, nodes)
        |> Enum.to_list()
      end

      # Missing middle transaction
      MockClient
      |> expect(:send_message, fn
        _, %GetTransactionChain{address: ^genesis, paging_state: nil}, _ ->
          {:ok, %TransactionList{transactions: [tx1, tx3, tx4]}}
      end)

      expected_message =
        "Replication failed to fetch previous chain after #{Base.encode16(tx1.address)}"

      assert_raise RuntimeError, expected_message, fn ->
        genesis
        |> TransactionContext.stream_transaction_chain(addr3, nodes)
        |> Enum.to_list()
      end

      # Missing last transaction
      MockClient
      |> expect(:send_message, fn
        _, %GetTransactionChain{address: ^genesis, paging_state: nil}, _ ->
          {:ok, %TransactionList{transactions: [tx1, tx2]}}
      end)

      expected_message =
        "Replication failed to fetch previous chain after #{Base.encode16(tx2.address)}"

      assert_raise RuntimeError, expected_message, fn ->
        genesis
        |> TransactionContext.stream_transaction_chain(addr3, nodes)
        |> Enum.to_list()
      end
    end
  end

  test "fetch_transaction_unspent_outputs/1 should retrieve the utxos of the chain" do
    v_utxo =
      %UnspentOutput{
        from: random_address(),
        amount: 19_300_000,
        type: :UCO,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
      |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())

    genesis_address = random_address()

    MockClient
    |> expect(:send_message, fn _, %GetUnspentOutputs{address: ^genesis_address}, _ ->
      {:ok, %UnspentOutputList{unspent_outputs: [v_utxo]}}
    end)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: ~U[2024-01-01 00:00:00Z]
    })

    assert [^v_utxo] = TransactionContext.fetch_transaction_unspent_outputs(genesis_address)
  end

  def connect_to_n_nodes(n) do
    Enum.each(1..n, fn i ->
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000 + i,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })
    end)
  end
end
