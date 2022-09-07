defmodule Archethic.BeaconChain.SlotTimerTest do
  use ArchethicCase

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.SubsetRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Crypto

  setup do
    Enum.each(BeaconChain.list_subsets(), fn subset ->
      Registry.register(SubsetRegistry, subset, [])
    end)

    :ok
  end

  test "receive create_slot message after timer elapsed" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
    assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
    send(pid, :node_up)
    assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)

    current = DateTime.utc_now()

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now()
    })

    receive do
      {:create_slot, time} ->
        assert 1 == DateTime.diff(time, current)
    end
  end

  test "should not send create slot event if node is unavailable" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
    assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
    send(pid, :node_up)
    assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: false,
      authorization_date: DateTime.utc_now()
    })

    refute_receive({:create_slot, _}, 1200)
  end

  test "handle_info/3 receive a slot creation message" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
    assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
    send(pid, :node_up)
    assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now()
    })

    send(pid, :new_slot)

    Process.sleep(200)

    nb_create_slot_messages =
      self()
      |> :erlang.process_info(:messages)
      |> elem(1)
      |> Enum.filter(&match?({:create_slot, _}, &1))
      |> length()

    assert nb_create_slot_messages == 256
  end

  test "next_slot/1 should get the slot time from a given date" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
    assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
    send(pid, :node_up)
    assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)

    now = DateTime.utc_now()
    next_slot_time = SlotTimer.next_slot(now)
    assert :gt == DateTime.compare(next_slot_time, now)
  end

  test "previous_slot/2 should retrieve the previous slot time from a date" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
    assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
    send(pid, :node_up)
    assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)

    now = DateTime.utc_now()
    previous_slot_time = SlotTimer.previous_slot(now)
    assert :gt == DateTime.compare(now, previous_slot_time)
  end

  describe "SlotTimer Behavior During start" do
    test "should wait for node :up message" do
      :persistent_term.put(:archethic_up, nil)

      {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
      assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
    end

    test "should start timer post node :up message" do
      :persistent_term.put(:archethic_up, nil)

      {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
      assert %{interval: "*/1 * * * * * *"} = :sys.get_state(pid)
      send(pid, :node_up)
      assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)
    end

    test "should use :persistent_term archethic_up when slot timer crashes" do
      :persistent_term.put(:archethic_up, :up)
      {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])
      assert %{interval: "*/1 * * * * * *", timer: _} = :sys.get_state(pid)
    end
  end
end
