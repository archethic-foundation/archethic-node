defmodule Archethic.P2P.BootstrappingSeedsTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.BootstrappingSeeds
  alias Archethic.P2P.Node

  doctest BootstrappingSeeds

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    Application.delete_env(:archethic, BootstrappingSeeds)

    :ok
  end

  setup_all do
    {pub1, _} = Crypto.generate_deterministic_keypair("seed")
    {pub2, _} = Crypto.generate_deterministic_keypair("seed2")

    seed_str = """
    127.0.0.1:3005:#{Base.encode16(pub1)}:tcp
    127.0.0.1:3003:#{Base.encode16(pub2)}:tcp
    """

    [seed_str: seed_str]
  end

  describe "start_link/1" do
    test "should load from DB the bootstrapping seeds", context do
      seed_str = context.seed_str

      MockDB
      |> expect(:get_bootstrap_info, fn "bootstrapping_seeds" -> seed_str end)

      {:ok, pid} = BootstrappingSeeds.start_link()

      %{seeds: seeds} = :sys.get_state(pid)
      assert [%Node{port: 3005}, %Node{port: 3003}] = seeds
    end

    test "should load from conf if present" do
      MockDB
      |> expect(:get_bootstrap_info, fn "bootstrapping_seeds" -> nil end)

      {:ok, pid} =
        BootstrappingSeeds.start_link(
          genesis_seeds:
            "127.0.0.1:3002:0000DB9539BEEA59B659DDC0A1E20910F74BDCFA41166BB1DF0D6489506BB137D491:tcp"
        )

      %{seeds: seeds} = :sys.get_state(pid)

      assert [%Node{port: 3002, first_public_key: node_key, transport: :tcp}] = seeds

      assert node_key ==
               Base.decode16!(
                 "0000DB9539BEEA59B659DDC0A1E20910F74BDCFA41166BB1DF0D6489506BB137D491"
               )
    end
  end

  test "list/0 should return the list of P2P seeds", context do
    seed_str = context.seed_str

    MockDB
    |> expect(:get_bootstrap_info, fn "bootstrapping_seeds" -> seed_str end)

    {:ok, _pid} = BootstrappingSeeds.start_link()

    assert [%Node{port: 3005, transport: :tcp}, %Node{port: 3003, transport: :tcp}] =
             BootstrappingSeeds.list()
  end

  test "update/1 should refresh the seeds and flush them to disk", context do
    seed_str = context.seed_str

    me = self()

    MockDB
    |> expect(:get_bootstrap_info, fn "bootstrapping_seeds" -> seed_str end)
    |> expect(:set_bootstrap_info, fn "bootstrapping_seeds", seeds ->
      send(me, {:seeds, seeds})
      :ok
    end)

    {:ok, _pid} = BootstrappingSeeds.start_link()

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

    new_seeds_stringified = BootstrappingSeeds.nodes_to_seeds(new_seeds)
    assert_received {:seeds, ^new_seeds_stringified}
  end

  test "when receive a node update message should update the seeds list with the top nodes" do
    {:ok, _pid} =
      BootstrappingSeeds.start_link(
        genesis_seeds:
          "127.0.0.1:3002:0000DB9539BEEA59B659DDC0A1E20910F74BDCFA41166BB1DF0D6489506BB137D491:tcp"
      )

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3003,
      http_port: 4000,
      first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      transport: :tcp,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3004,
      http_port: 4000,
      first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      transport: :tcp,
      available?: true,
      authorized?: false
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3005,
      http_port: 4000,
      first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      transport: :tcp,
      available?: false,
      authorized?: false
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3006,
      http_port: 4000,
      first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      transport: :tcp,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    Process.sleep(200)

    assert Enum.all?(BootstrappingSeeds.list(), &(&1.port in [3003, 3006]))
  end
end
