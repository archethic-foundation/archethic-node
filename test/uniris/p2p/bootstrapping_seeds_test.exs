defmodule Uniris.P2P.BootstrappingSeedsTest do
  use ExUnit.Case

  alias Uniris.Crypto

  alias Uniris.P2P.BootstrappingSeeds
  alias Uniris.P2P.Node

  doctest BootstrappingSeeds

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    Application.delete_env(:uniris, BootstrappingSeeds)

    file_path = Application.app_dir(:uniris, "priv/p2p/seeds_test")

    MockCrypto
    |> stub(:node_public_key, fn _ -> :crypto.strong_rand_bytes(32) end)

    on_exit(fn ->
      File.rm(file_path)
    end)

    {:ok, %{file_path: file_path}}
  end

  describe "start_link/1" do
    test "should load from file the bootstrapping seeds", %{file_path: file_path} do
      {pub1, _} = Crypto.generate_deterministic_keypair("seed")
      {pub2, _} = Crypto.generate_deterministic_keypair("seed2")

      seed_str = """
      127.0.0.1:3005:#{Base.encode16(pub1)}:tcp
      127.0.0.1:3003:#{Base.encode16(pub2)}:tcp
      """

      File.write(file_path, seed_str, [:write])

      {:ok, pid} = BootstrappingSeeds.start_link(file: file_path)

      %{seeds: seeds, file: file} = :sys.get_state(pid)

      assert file == file_path
      assert [%Node{port: 3005}, %Node{port: 3003}] = seeds
    end

    test "should load from conf if present" do
      Application.put_env(:uniris, BootstrappingSeeds,
        seeds:
          "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8:tcp"
      )

      {:ok, pid} = BootstrappingSeeds.start_link()

      %{seeds: seeds, file: file} = :sys.get_state(pid)
      assert file == ""

      assert [%Node{port: 3002, first_public_key: node_key, transport: :tcp}] = seeds

      assert node_key ==
               Base.decode16!(
                 "00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"
               )
    end
  end

  test "list/0 should return the list of P2P seeds", %{file_path: file_path} do
    {pub1, _} = Crypto.generate_deterministic_keypair("seed")
    {pub2, _} = Crypto.generate_deterministic_keypair("seed2")

    seed_str = """
    127.0.0.1:3005:#{Base.encode16(pub1)}:tcp
    127.0.0.1:3003:#{Base.encode16(pub2)}:tcp
    """

    File.write(file_path, seed_str, [:write])

    {:ok, _pid} = BootstrappingSeeds.start_link(file: file_path)

    assert [%Node{port: 3005, transport: :tcp}, %Node{port: 3003, transport: :tcp}] =
             BootstrappingSeeds.list()
  end

  test "update/1 should refresh the seeds and flush them to disk", %{file_path: file_path} do
    {pub1, _} = Crypto.generate_deterministic_keypair("seed")
    {pub2, _} = Crypto.generate_deterministic_keypair("seed2")

    seed_str = """
    127.0.0.1:3005:#{Base.encode16(pub1)}:tcp
    127.0.0.1:3003:#{Base.encode16(pub2)}:tcp
    """

    File.write(file_path, seed_str, [:write])

    {:ok, _pid} = BootstrappingSeeds.start_link(file: file_path)

    assert [%Node{port: 3005}, %Node{port: 3003}] = BootstrappingSeeds.list()

    new_seeds = [
      %Node{
        ip: {90, 20, 10, 20},
        port: 3002,
        first_public_key: :crypto.strong_rand_bytes(32),
        transport: :tcp
      },
      %Node{
        ip: {100, 50, 115, 80},
        port: 3002,
        first_public_key: :crypto.strong_rand_bytes(32),
        transport: :tcp
      }
    ]

    assert :ok = BootstrappingSeeds.update(new_seeds)
    assert new_seeds == BootstrappingSeeds.list()

    assert BootstrappingSeeds.nodes_to_seeds(new_seeds) == File.read!(file_path)
  end
end
