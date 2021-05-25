defmodule Uniris.BeaconChain.SlotTimerTest do
  use UnirisCase

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.SubsetRegistry

  alias Uniris.Crypto

  alias Uniris.P2P.Node

  setup do
    Enum.each(BeaconChain.list_subsets(), fn subset ->
      Registry.register(SubsetRegistry, subset, [])
    end)

    :ok
  end

  test "should start scheduler when the current become authorized" do
    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])

    send(
      pid,
      {:node_update, %Node{authorized?: true, first_public_key: Crypto.node_public_key()}}
    )

    assert %{timer: _} = :sys.get_state(pid)
  end

  test "should stop scheduler when the current become unauthorized" do
    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])

    send(
      pid,
      {:node_update, %Node{authorized?: true, first_public_key: Crypto.node_public_key()}}
    )

    assert %{timer: timer} = :sys.get_state(pid)

    send(
      pid,
      {:node_update, %Node{authorized?: false, first_public_key: Crypto.node_public_key()}}
    )

    Process.sleep(200)
    assert false == Process.read_timer(timer)
  end

  test "receive create_slot message after timer elapsed" do
    {:ok, pid} = SlotTimer.start_link([interval: "*/1 * * * * * *"], [])

    send(
      pid,
      {:node_update, %Node{authorized?: true, first_public_key: Crypto.node_public_key()}}
    )

    current = DateTime.utc_now()

    receive do
      {:create_slot, time} ->
        assert 1 == DateTime.diff(time, current)
    end
  end

  test "handle_info/3 receive a slot creation message" do
    {:ok, pid} = SlotTimer.start_link([interval: "0 * * * * * *"], [])

    send(
      pid,
      {:node_update, %Node{authorized?: true, first_public_key: Crypto.node_public_key()}}
    )

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
    {:ok, _pid} = SlotTimer.start_link([interval: "0 * * * * * *", trigger_offset: 0], [])
    now = DateTime.utc_now()
    next_slot_time = SlotTimer.next_slot(now)
    assert 1 == abs(now.minute - next_slot_time.minute)
  end

  test "previous_slot/2 should retrieve the previous slot time from a date" do
    {:ok, _pid} = SlotTimer.start_link([interval: "0 * * * * * *"], [])

    now = DateTime.utc_now()
    previous_slot_time = SlotTimer.previous_slot(now)
    assert :gt == DateTime.compare(now, previous_slot_time)
  end
end
