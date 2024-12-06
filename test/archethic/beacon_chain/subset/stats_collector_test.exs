defmodule Archethic.BeaconChain.Subset.StatsCollectorTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.NetworkCoordinates
  alias Archethic.BeaconChain.Subset.StatsCollector
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.Utils.JobCache
  alias Archethic.Utils.JobCacheRegistry

  import ArchethicCase
  import Mock

  @timeout 1_000

  setup do
    {:ok, pid} = StatsCollector.start_link([])

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1, :day)
    })

    {:ok, %{pid: pid}}
  end

  test "is subscribed to events", %{pid: pid} do
    assert [:self_repair_sync, :next_summary_time] = Registry.keys(Archethic.PubSubRegistry, pid)
  end

  test "should react to events" do
    next_summary_time = DateTime.utc_now()

    with_mocks([
      {JobCache, [], start: fn _ -> :ok end, stop: fn _ -> :ok end},
      {BeaconChain, [:passthrough], get_network_stats: fn _, _ -> %{} end},
      {NetworkCoordinates, [],
       timeout: fn -> @timeout end, fetch_network_stats: fn _summary_time, _ -> Nx.tensor(0) end}
    ]) do
      send(StatsCollector, {:next_summary_time, next_summary_time})
      _ = :sys.get_state(StatsCollector)
      assert_called_exactly(JobCache.start(:_), 2)

      send(StatsCollector, :self_repair_sync)
      _ = :sys.get_state(StatsCollector)
      assert_called_exactly(JobCache.stop(:_), 2)
    end
  end

  test "get/1 should return the stats of the subsets current node is elected to store" do
    subset1 = :binary.encode_unsigned(0)
    subset2 = :binary.encode_unsigned(1)
    node1_public_key = random_public_key()
    node2_public_key = random_public_key()
    node3_public_key = random_public_key()
    node4_public_key = random_public_key()
    current_node = P2P.get_node_info()

    with_mocks([
      {BeaconChain, [:passthrough],
       get_network_stats: fn
         ^subset1, _ ->
           %{
             node1_public_key => [%{latency: 1}],
             node2_public_key => [%{latency: 1}]
           }

         ^subset2, _ ->
           %{
             node3_public_key => [%{latency: 10}],
             node4_public_key => [%{latency: 10}]
           }
       end},
      {Election, [],
       beacon_storage_nodes: fn
         ^subset1, _, _ -> [current_node]
         ^subset2, _, _ -> [current_node]
         _, _, _ -> []
       end},
      {NetworkCoordinates, [], timeout: fn -> @timeout end}
    ]) do
      summary_time = DateTime.utc_now()
      PubSub.notify_next_summary_time(summary_time)

      assert %{
               ^subset1 => %{
                 ^node1_public_key => [
                   %{latency: 1}
                 ],
                 ^node2_public_key => [
                   %{latency: 1}
                 ]
               },
               ^subset2 => %{
                 ^node3_public_key => [
                   %{latency: 10}
                 ],
                 ^node4_public_key => [
                   %{latency: 10}
                 ]
               }
             } = StatsCollector.get(summary_time, @timeout)
    end
  end

  test "get/1 should start the job and reply if requested before the event happens" do
    subset1 = :binary.encode_unsigned(0)
    subset2 = :binary.encode_unsigned(1)
    node1_public_key = random_public_key()
    node2_public_key = random_public_key()
    node3_public_key = random_public_key()
    node4_public_key = random_public_key()
    current_node = P2P.get_node_info()

    summary_time = DateTime.utc_now()

    assert 0 =
             Registry.lookup(JobCacheRegistry, {:get, summary_time})
             |> length

    with_mocks([
      {BeaconChain, [:passthrough],
       get_network_stats: fn
         ^subset1, _ ->
           %{
             node1_public_key => [%{latency: 1}],
             node2_public_key => [%{latency: 1}]
           }

         ^subset2, _ ->
           %{
             node3_public_key => [%{latency: 10}],
             node4_public_key => [%{latency: 10}]
           }
       end},
      {Election, [],
       beacon_storage_nodes: fn
         ^subset1, _, _ -> [current_node]
         ^subset2, _, _ -> [current_node]
         _, _, _ -> []
       end},
      {NetworkCoordinates, [], timeout: fn -> @timeout end}
    ]) do
      assert %{
               ^subset1 => %{
                 ^node1_public_key => [
                   %{latency: 1}
                 ],
                 ^node2_public_key => [
                   %{latency: 1}
                 ]
               },
               ^subset2 => %{
                 ^node3_public_key => [
                   %{latency: 10}
                 ],
                 ^node4_public_key => [
                   %{latency: 10}
                 ]
               }
             } = StatsCollector.get(summary_time, @timeout)
    end

    assert 1 =
             Registry.lookup(JobCacheRegistry, {:get, summary_time})
             |> length
  end

  test "fetch/1 should return the stats of all subsets" do
    subset1 = :binary.encode_unsigned(0)
    subset2 = :binary.encode_unsigned(1)
    current_node = P2P.get_node_info()

    tensor =
      Nx.tensor([
        [0, 0, 36, 67, 45, 64, 0, 176, 43, 63, 190, 44, 75, 0, 146],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [36, 0, 0, 44, 63, 38, 0, 176, 47, 76, 167, 50, 65, 0, 142],
        [67, 0, 44, 0, 47, 75, 0, 169, 52, 70, 186, 58, 70, 0, 159],
        [45, 0, 63, 47, 0, 51, 0, 182, 53, 83, 187, 58, 107, 0, 142],
        [64, 0, 38, 75, 51, 0, 0, 178, 46, 48, 193, 80, 72, 0, 149],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [176, 0, 176, 169, 182, 178, 0, 0, 151, 162, 196, 191, 143, 0, 195],
        [43, 0, 47, 52, 53, 46, 0, 151, 0, 182, 166, 115, 91, 0, 109],
        [63, 0, 76, 70, 83, 48, 0, 162, 182, 0, 167, 105, 144, 0, 124],
        [190, 0, 167, 186, 187, 193, 0, 196, 166, 167, 0, 182, 165, 0, 109],
        [44, 0, 50, 58, 58, 80, 0, 191, 115, 105, 182, 0, 82, 0, 154],
        [75, 0, 65, 70, 107, 72, 0, 143, 91, 144, 165, 82, 0, 0, 160],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [146, 0, 142, 159, 142, 149, 0, 195, 109, 124, 109, 154, 160, 0, 0]
      ])

    with_mocks([
      {BeaconChain, [:passthrough], get_network_stats: fn _, _ -> %{} end},
      {NetworkCoordinates, [],
       timeout: fn -> @timeout end,
       fetch_network_stats: fn _summary_time, _ ->
         tensor
       end},
      {Election, [],
       beacon_storage_nodes: fn
         ^subset1, _, _ -> [current_node]
         ^subset2, _, _ -> [current_node]
         _, _, _ -> []
       end}
    ]) do
      summary_time = DateTime.utc_now()
      PubSub.notify_next_summary_time(summary_time)

      assert ^tensor = StatsCollector.fetch(summary_time, @timeout)
    end
  end

  test "fetch/1 should start the job and reply if requested before the event happens" do
    subset1 = :binary.encode_unsigned(0)
    subset2 = :binary.encode_unsigned(1)
    current_node = P2P.get_node_info()

    summary_time = DateTime.utc_now()

    assert 0 =
             Registry.lookup(JobCacheRegistry, {:fetch, summary_time})
             |> length

    with_mocks([
      {BeaconChain, [:passthrough], get_network_stats: fn _, _ -> %{} end},
      {NetworkCoordinates, [],
       timeout: fn -> @timeout end,
       fetch_network_stats: fn _summary_time, _ ->
         Nx.tensor(1)
       end},
      {Election, [],
       beacon_storage_nodes: fn
         ^subset1, _, _ -> [current_node]
         ^subset2, _, _ -> [current_node]
         _, _, _ -> []
       end}
    ]) do
      # can't compare tensor directly so we compare serialization
      expected = Nx.tensor(1) |> Nx.to_binary()
      assert ^expected = StatsCollector.fetch(summary_time, @timeout) |> Nx.to_binary()
    end

    assert 1 =
             Registry.lookup(JobCacheRegistry, {:fetch, summary_time})
             |> length
  end
end
