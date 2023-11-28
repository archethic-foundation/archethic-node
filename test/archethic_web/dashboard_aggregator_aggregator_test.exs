defmodule ArchethicWeb.DashboardAggregatorAggregatorTest do
  alias ArchethicWeb.DashboardAggregatorAggregator
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetDashboardData
  alias Archethic.P2P.Message.DashboardData

  use ArchethicCase

  import Mox
  import ArchethicCase

  setup do
    # we'll act as if the node is not up for these tests
    # (otherwise we would have to mock in the setup)
    :persistent_term.put(:archethic_up, nil)

    current_node_pkey = random_public_key()
    other_node_pkey = random_public_key()

    P2P.add_and_connect_node(%Node{
      ip: {122, 12, 0, 5},
      port: 3000,
      first_public_key: current_node_pkey,
      last_public_key: current_node_pkey,
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    P2P.add_and_connect_node(%Node{
      ip: {122, 12, 0, 6},
      port: 3000,
      first_public_key: other_node_pkey,
      last_public_key: other_node_pkey,
      network_patch: "BBB",
      geo_patch: "BBB",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    # the DashboardAggregatorAggregator is already started and supervised
    # we kill it to reset it's data on every test
    DashboardAggregatorAggregator
    |> Process.whereis()
    |> Process.exit(:kill)

    Process.sleep(10)

    {:ok, %{current_node_pkey: current_node_pkey, other_node_pkey: other_node_pkey}}
  end

  test "should fetch the external data as soon as process is created", %{
    current_node_pkey: current_node_pkey,
    other_node_pkey: other_node_pkey
  } do
    MockClient
    |> expect(:send_message, 2, fn
      %Node{first_public_key: ^current_node_pkey}, %GetDashboardData{}, _ ->
        {:ok,
         %DashboardData{
           buckets: %{
             ~U[2023-11-23 16:00:00Z] => [1],
             ~U[2023-11-23 16:01:00Z] => [2, 3]
           }
         }}

      %Node{first_public_key: ^other_node_pkey}, %GetDashboardData{}, _ ->
        {:ok,
         %DashboardData{
           buckets: %{
             ~U[2023-11-23 16:00:00Z] => [4, 5, 6],
             ~U[2023-11-23 16:01:00Z] => [7]
           }
         }}
    end)

    Archethic.PubSub.notify_node_status(:node_up)
    Process.sleep(10)

    result = DashboardAggregatorAggregator.get_all()

    assert 4 = length(Map.keys(result))
    assert Map.has_key?(result, {current_node_pkey, ~U[2023-11-23 16:00:00Z]})
    assert Map.has_key?(result, {current_node_pkey, ~U[2023-11-23 16:01:00Z]})
    assert Map.has_key?(result, {other_node_pkey, ~U[2023-11-23 16:00:00Z]})
    assert Map.has_key?(result, {other_node_pkey, ~U[2023-11-23 16:01:00Z]})
  end

  test "buckets are cleaned automatically", %{
    current_node_pkey: current_node_pkey,
    other_node_pkey: other_node_pkey
  } do
    now_timestamp = DateTime.to_unix(DateTime.utc_now())
    now_rounded = DateTime.from_unix!(now_timestamp - rem(now_timestamp, 60))

    expired_timestamp = DateTime.to_unix(DateTime.utc_now() |> DateTime.add(-2, :hour))
    expired_rounded = DateTime.from_unix!(expired_timestamp - rem(expired_timestamp, 60))

    MockClient
    |> expect(:send_message, 2, fn
      %Node{first_public_key: ^current_node_pkey}, %GetDashboardData{}, _ ->
        {:ok,
         %DashboardData{
           buckets: %{
             now_rounded => [1],
             expired_rounded => [2, 3]
           }
         }}

      %Node{first_public_key: ^other_node_pkey}, %GetDashboardData{}, _ ->
        {:ok,
         %DashboardData{
           buckets: %{
             now_rounded => [4, 5, 6],
             expired_rounded => [7]
           }
         }}
    end)

    Archethic.PubSub.notify_node_status(:node_up)
    Process.sleep(10)

    result = DashboardAggregatorAggregator.get_all()
    assert 4 = length(Map.keys(result))

    # trigger a clean
    send(Process.whereis(DashboardAggregatorAggregator), :clean_state)

    buckets = DashboardAggregatorAggregator.get_all()
    assert 2 = length(Map.keys(buckets))

    assert Map.has_key?(result, {current_node_pkey, now_rounded})
    assert Map.has_key?(result, {other_node_pkey, now_rounded})
  end
end
