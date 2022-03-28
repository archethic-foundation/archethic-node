defmodule ArchEthic.DB.EmbeddedImpl.ReaderTest do
  use ArchEthicCase

  alias ArchEthic.DB.EmbeddedImpl.Index
  alias ArchEthic.DB.EmbeddedImpl.Reader
  alias ArchEthic.DB.EmbeddedImpl.Writer

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

  @tag :benchmark
  test "benchmark read tx" do
    genesis_address = :crypto.strong_rand_bytes(32)

    Benchee.run(
      %{
        "read_transaction" => fn tx_address ->
          Reader.get_transaction(tx_address)
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

        Writer.append_transaction(genesis_address, tx)
        tx.address
      end
    )
  end
end
