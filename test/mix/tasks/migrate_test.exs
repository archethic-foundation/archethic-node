defmodule Mix.Tasks.Archethic.MigrateTest do
  use ArchethicCase

  alias Archethic.Crypto
  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Mix.Tasks.Archethic.Migrate

  import Mox

  describe "run/1" do
    setup do
      EmbeddedImpl.Supervisor.start_link()
      migration_path = EmbeddedImpl.filepath() |> ChainWriter.migration_file_path()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3001,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      on_exit(fn -> Process.sleep(50) end)

      %{migration_path: migration_path}
    end

    test "should create migration file with current version", %{
      migration_path: migration_path
    } do
      refute File.exists?(migration_path)

      Migrate.run("0.0.1")

      assert File.exists?(migration_path)
      assert "0.0.1" = File.read!(migration_path)
    end

    test "should not update version number on version without migration", %{
      migration_path: migration_path
    } do
      Migrate.run("0.0.2")
      assert "0.0.2" = File.read!(migration_path)

      Migrate.run("0.0.3")
      assert "0.0.2" = File.read!(migration_path)
    end

    test "should run all missed upgrade", %{
      migration_path: migration_path
    } do
      File.write!(migration_path, "0.0.0")

      MockDB
      |> expect(:transaction_exists?, fn "0.0.1", _ -> true end)
      |> expect(:transaction_exists?, fn "0.0.2", _ -> true end)

      Migrate.run("0.0.3")
      assert "0.0.2" = File.read!(migration_path)
    end

    test "should not run migration already done", %{
      migration_path: migration_path
    } do
      File.write!(migration_path, "0.0.1")

      me = self()

      MockDB
      |> stub(:transaction_exists?, fn version, _ -> send(me, version) end)

      Migrate.run("0.0.2")

      refute_receive "0.0.1"
      assert_receive "0.0.2"
    end
  end
end
