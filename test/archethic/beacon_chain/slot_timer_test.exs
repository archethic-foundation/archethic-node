defmodule Archethic.BeaconChain.SlotTimerTest do
  use ArchethicCase

  alias Archethic.BeaconChain.SlotTimer

  alias Archethic.PubSub

  doctest SlotTimer

  setup do
    Application.put_env(:archethic, SlotTimer, interval: "*/1 * * * * * *")
    :ok
  end

  test "send current_epoch_of_slot_timer message after timer elapsed" do
    :persistent_term.put(:archethic_up, nil)

    PubSub.register_to_current_epoch_of_slot_time()

    {:ok, pid} = SlotTimer.start_link()
    send(pid, :node_up)

    current = DateTime.utc_now()

    assert_receive {:current_epoch_of_slot_timer, time}, 1100
    assert 1 == DateTime.diff(time, current)
  end

  # describe "SlotTimer Behavior During start" do
  test "should wait for :node_up message" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link()
    state = :sys.get_state(pid)
    refute Map.has_key?(state, :timer)
  end

  test "should start timer post node_up message and stop it after node_down" do
    :persistent_term.put(:archethic_up, nil)

    {:ok, pid} = SlotTimer.start_link()
    send(pid, :node_up)
    state = :sys.get_state(pid)
    assert Map.has_key?(state, :timer)

    send(pid, :node_down)
    state = :sys.get_state(pid)
    refute Map.has_key?(state, :timer)
  end

  test "should use :persistent_term archethic_up when slot timer crashes" do
    :persistent_term.put(:archethic_up, :up)
    {:ok, pid} = SlotTimer.start_link()
    state = :sys.get_state(pid)
    assert Map.has_key?(state, :timer)
  end
end
