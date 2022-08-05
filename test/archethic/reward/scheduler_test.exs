defmodule Archethic.Reward.SchedulerTest do
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.StartMining

  alias Archethic.Reward.Scheduler

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      average_availability: 1.0
    })
  end

  test "should initiate the reward scheduler and trigger mint reward" do
    MockDB
    |> stub(:get_latest_burned_fees, fn -> 0 end)

    assert {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")

    assert %{interval: "*/1 * * * * *"} = :sys.get_state(pid)

    send(
      pid,
      {:node_update,
       %Node{
         authorized?: true,
         available?: true,
         first_public_key: Crypto.first_node_public_key()
       }}
    )

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :mint_rewards}, 3_000
  end

  test "should send mint transaction when burning fees > 0 and node reward transaction" do
    MockDB
    |> stub(:get_latest_burned_fees, fn -> 15_000 end)

    me = self()

    assert {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")

    MockClient
    |> stub(:send_message, fn
      _, %StartMining{transaction: %{type: type}}, _ when type == :mint_rewards ->
        send(pid, {:new_transaction, nil, :mint_rewards, nil})
        send(me, type)

      _, %StartMining{transaction: %{type: type}}, _ when type == :node_rewards ->
        send(me, type)
    end)

    send(
      pid,
      {:node_update,
       %Node{
         authorized?: true,
         available?: true,
         first_public_key: Crypto.first_node_public_key()
       }}
    )

    assert_receive :mint_rewards, 1_500
    assert_receive :node_rewards, 1_500
  end

  test "should not send transaction when burning fees = 0 and should send node rewards" do
    MockDB
    |> stub(:get_latest_burned_fees, fn -> 0 end)

    me = self()

    MockClient
    |> stub(:send_message, fn _, %StartMining{transaction: %{type: type}}, _ ->
      send(me, type)
    end)

    assert {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")

    send(
      pid,
      {:node_update,
       %Node{
         authorized?: true,
         available?: true,
         first_public_key: Crypto.first_node_public_key()
       }}
    )

    refute_receive :mint_rewards, 1_200
    assert_receive :node_rewards, 1_500
  end
end
