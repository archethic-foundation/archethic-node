defmodule Uniris.P2P.BootstrappingSeedsTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.BootstrappingSeeds
  alias Uniris.P2P.Node

  alias Uniris.Utils

  doctest BootstrappingSeeds

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    Application.delete_env(:uniris, BootstrappingSeeds)

    file_path = Utils.mut_dir("priv/p2p/seeds_test")
    File.mkdir_p(Path.dirname(file_path))

    MockCrypto
    |> stub(:last_public_key, fn -> :crypto.strong_rand_bytes(32) end)

    on_exit(fn ->
      File.rm_rf(Path.dirname(file_path))
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
      {:ok, pid} =
        BootstrappingSeeds.start_link(
          seeds:
            "127.0.0.1:3002:00DB9539BEEA59B659DDC0A1E20910F74BDCFA41166BB1DF0D6489506BB137D491:tcp"
        )

      %{seeds: seeds, file: file} = :sys.get_state(pid)
      assert file == ""

      assert [%Node{port: 3002, first_public_key: node_key, transport: :tcp}] = seeds

      assert node_key ==
               Base.decode16!(
                 "00DB9539BEEA59B659DDC0A1E20910F74BDCFA41166BB1DF0D6489506BB137D491"
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

  test "when receive a node updat message should update the seeds list with the top nodes" do
    {:ok, _pid} =
      BootstrappingSeeds.start_link(
        seeds:
          "127.0.0.1:3002:00DB9539BEEA59B659DDC0A1E20910F74BDCFA41166BB1DF0D6489506BB137D491:tcp"
      )

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3003,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      transport: :tcp,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3004,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      transport: :tcp,
      available?: true,
      authorized?: false
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3005,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      transport: :tcp,
      available?: false,
      authorized?: false
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3006,
      first_public_key: :crypto.strong_rand_bytes(32),
      last_public_key: :crypto.strong_rand_bytes(32),
      transport: :tcp,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    assert Enum.all?(BootstrappingSeeds.list(), &(&1.port in [3003, 3006]))
  end
end
