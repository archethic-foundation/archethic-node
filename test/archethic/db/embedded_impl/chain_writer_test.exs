defmodule ArchEthic.DB.EmbeddedImpl.ChainWriterTest do
  use ArchEthicCase

  alias ArchEthic.DB.EmbeddedImpl.ChainIndex
  alias ArchEthic.DB.EmbeddedImpl.ChainWriter

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

  describe "start_link/1" do
    test "should initialize the folders of the embedded database", %{db_path: db_path} do
      assert File.dir?(Application.app_dir(:archethic, "data_test"))
      assert File.dir?(Application.app_dir(:archethic, "data_test/chains"))
    end
  end

  @tag :benchmark
  test "benchmark append tx" do
    genesis_address = :crypto.strong_rand_bytes(32)

    Benchee.run(
      %{
        "append_transaction" => fn tx ->
          ChainWriter.append_transaction(genesis_address, tx)
        end
      },
      inputs: %{
        "small size (1 KB)" => :crypto.strong_rand_bytes(1_000),
        "medium size (10 KB)" => :crypto.strong_rand_bytes(10000),
        "big size (1 MB)" => :crypto.strong_rand_bytes(1_000_000)
      },
      before_each: fn content ->
        TransactionFactory.create_valid_transaction([],
          seed: :crypto.strong_rand_bytes(32),
          content: content
        )
      end
    )
  end
end
