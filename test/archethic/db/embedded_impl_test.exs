defmodule ArchEthic.DB.EmbeddedTest do
  use ArchEthicCase

  alias ArchEthic.DB.EmbeddedImpl
  alias ArchEthic.DB.EmbeddedImpl.Encoding
  alias ArchEthic.DB.EmbeddedImpl.Index
  alias ArchEthic.DB.EmbeddedImpl.Writer

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionFactory

  setup do
    Index.start_link()
    db_path = Application.app_dir(:archethic, "data_test")
    {:ok, _} = Writer.start_link(path: db_path)

    on_exit(fn ->
      File.rm_rf!(Application.app_dir(:archethic, "data_test"))
    end)

    %{db_path: db_path}
  end

  describe "write_transaction_chain/1" do
    test "should persist a transaction chain in the dedicated file", %{db_path: db_path} do
      tx = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx])

      genesis_address = Transaction.previous_address(tx)

      filename = Path.join(db_path, "chains/#{Base.encode16(genesis_address)}")
      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx)
      filesize = byte_size(contents)

      assert {:ok,
              %{file: ^filename, size: ^filesize, offset: 0, genesis_address: ^genesis_address}} =
               Index.get_tx_entry(tx.address)
    end

    test "should append transaction to an existing chain", %{db_path: db_path} do
      tx1 = TransactionFactory.create_valid_transaction([], index: 0)
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      genesis_address = Transaction.previous_address(tx1)

      tx2 = TransactionFactory.create_valid_transaction([], index: 1)
      :ok = EmbeddedImpl.write_transaction_chain([tx1, tx2])

      filename = Path.join(db_path, "chains/#{Base.encode16(genesis_address)}")

      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx1) <> Encoding.encode(tx2)

      size_tx1 = Encoding.encode(tx1) |> byte_size()
      size_tx2 = Encoding.encode(tx2) |> byte_size()

      assert {:ok,
              %{file: ^filename, size: ^size_tx1, offset: 0, genesis_address: ^genesis_address}} =
               Index.get_tx_entry(tx1.address)

      assert {:ok,
              %{
                file: ^filename,
                size: ^size_tx2,
                offset: ^size_tx1,
                genesis_address: ^genesis_address
              }} = Index.get_tx_entry(tx2.address)
    end
  end

  describe "write_transaction/1" do
    test "should write single transaction to non existing chain", %{db_path: db_path} do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction(tx1)

      genesis_address = Transaction.previous_address(tx1)

      filename = Path.join(db_path, "chains/#{Base.encode16(genesis_address)}")

      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx1)
      size_tx1 = Encoding.encode(tx1) |> byte_size()

      assert {:ok,
              %{file: ^filename, size: ^size_tx1, offset: 0, genesis_address: ^genesis_address}} =
               Index.get_tx_entry(tx1.address)
    end

    test "should write single transaction and append to an existing chain", %{db_path: db_path} do
      tx1 = TransactionFactory.create_valid_transaction([], index: 0)
      :ok = EmbeddedImpl.write_transaction(tx1)

      tx2 = TransactionFactory.create_valid_transaction([], index: 1)
      :ok = EmbeddedImpl.write_transaction(tx2)

      genesis_address = Transaction.previous_address(tx1)
      filename = Path.join(db_path, "chains/#{Base.encode16(genesis_address)}")

      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx1) <> Encoding.encode(tx2)

      size_tx1 = Encoding.encode(tx1) |> byte_size
      size_tx2 = Encoding.encode(tx2) |> byte_size

      assert {:ok,
              %{
                file: ^filename,
                size: ^size_tx2,
                offset: ^size_tx1,
                genesis_address: ^genesis_address
              }} = Index.get_tx_entry(tx2.address)
    end
  end

  describe "transaction_exists?/1" do
    test "should return true when the transaction is present" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert EmbeddedImpl.transaction_exists?(tx1.address)
    end

    test "should return false when the transaction is present" do
      assert !EmbeddedImpl.transaction_exists?(:crypto.strong_rand_bytes(32))
    end
  end

  describe "get_transaction/2" do
    test "should an error when the transaction does not exists" do
      assert {:error, :transaction_not_exists} =
               EmbeddedImpl.get_transaction(:crypto.strong_rand_bytes(32))
    end

    test "should retrieve a transaction" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert {:ok, ^tx1} = EmbeddedImpl.get_transaction(tx1.address)
    end

    test "should filter with the given fields" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert {:ok, %Transaction{type: :transfer, address: nil}} =
               EmbeddedImpl.get_transaction(tx1.address, [:type])
    end

    test "should filter with nested fields" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert {:ok,
              %Transaction{
                validation_stamp: %ValidationStamp{
                  timestamp: %DateTime{},
                  ledger_operations: %LedgerOperations{fee: fee}
                }
              }} =
               EmbeddedImpl.get_transaction(tx1.address,
                 validation_stamp: [:timestamp, ledger_operations: :fee]
               )

      assert fee != 0.0
    end
  end

  describe "get_transaction_chain/2" do
    test "should return an empty list when the transaction chain is not found" do
      assert [] = EmbeddedImpl.get_transaction_chain(:crypto.strong_rand_bytes(32))
    end

    test "should return the list of all the transactions related to transaction's address chain" do
      tx1 = TransactionFactory.create_valid_transaction([], index: 0)

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: DateTime.add(DateTime.utc_now(), 100)
        )

      _genesis_address = Transaction.previous_address(tx1)

      :ok = EmbeddedImpl.write_transaction_chain([tx1, tx2])

      assert {[^tx1, ^tx2], false, nil} = EmbeddedImpl.get_transaction_chain(tx2.address)
    end

    test "should return a page and its paging state" do
      transactions =
        Enum.map(1..20, fn i ->
          TransactionFactory.create_valid_transaction([],
            index: i,
            timestamp: DateTime.utc_now() |> DateTime.add(i * 60)
          )
        end)

      EmbeddedImpl.write_transaction_chain(transactions)

      {page, true, paging_state} =
        EmbeddedImpl.get_transaction_chain(List.first(transactions).address)

      assert length(page) == 10
      assert page == Enum.take(transactions, 10)
      assert paging_state == List.last(page).address

      {page2, false, nil} = EmbeddedImpl.get_transaction_chain(List.first(transactions).address, [], paging_state: paging_state)
      assert length(page2) == 10
      assert page2 == Enum.slice(transactions, 10, 10)
    end
  end
end
