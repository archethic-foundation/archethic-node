defmodule ArchEthic.DB.EmbeddedImpl.ChainChainReader.est() do
  use ArchEthicCase

  alias ArchEthic.DB.EmbeddedImpl.ChainIndex
  alias ArchEthic.DB.EmbeddedImpl.ChainReader
  alias ArchEthic.DB.EmbeddedImpl.ChainChainWriter

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionFactory

  setup do
    ChainIndex.start_link()
    db_path = Application.app_dir(:archethic, "data_test")
    {:ok, _} = ChainWriter.start_link(path: db_path)

    on_exit(fn ->
      File.rm_rf!(Application.app_dir(:archethic, "data_test"))
    end)

    %{db_path: db_path}
  end

  @tag :benchmark
  test "benchmark read tx" do
    genesis_address = :crypto.strong_rand_bytes(32)

    Benchee.run(
      %{
        "read_transaction" => fn tx_address ->
          ChainReader.get_transaction(tx_address)
        end
      },
      inputs: %{
        "small size (1 KB)" => :crypto.strong_rand_bytes(1_000),
        "medium size (10 KB)" => :crypto.strong_rand_bytes(10000),
        "big size (1 MB)" => :crypto.strong_rand_bytes(1_000_000)
      },
      before_each: fn content ->
        tx =
          TransactionFactory.create_valid_transaction([],
            seed: :crypto.strong_rand_bytes(32),
            content: content
          )

        ChainWriter.append_transaction(genesis_address, tx)
        tx.address
      end
    )
  end

  @tag :benchmark
  test "benchmark read chain" do
    genesis_address = :crypto.strong_rand_bytes(32)

    Benchee.run(
      %{
        "read_chain" => fn tx_address ->
          ChainReader.get_transaction_chain(tx_address)
        end
      },
      inputs: %{
        "5" => 5,
        "50" => 50,
        "100" => 100,
        "500" => 500,
        "1000" => 1000
      },
      before_each: fn size_chain ->
        seed = :crypto.strong_rand_bytes(32)

        transactions =
          Enum.map(1..size_chain, fn i ->
            TransactionFactory.create_valid_transaction([],
              seed: seed,
              index: i,
              content: :crypto.strong_rand_bytes(1_000),
              timestamp: DateTime.add(DateTime.utc_now(), i * 60)
            )
          end)

        genesis_address =
          transactions
          |> List.first()
          |> Transaction.previous_address()

        Enum.each(transactions, &ChainWriter.append_transaction(genesis_address, &1))
        genesis_address
      end
    )
  end
end
