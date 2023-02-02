defmodule Archethic.BeaconChain.SummaryTimerTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.P2P.Message.NewBeaconSlot
  alias Archethic.P2P.Message.Ok

  import Mox

  setup do
    MockClient
    |> stub(:send_message, fn
      _node, %NewBeaconSlot{}, _timeout ->
        {:ok, %Ok{}}
    end)

    :ok
  end

  describe "next_summary/2" do
    test "should get the next summary time from a given date" do
      {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * * *"], [])
      now = ~U[2021-01-02 03:00:19.501Z]
      next_summary_time = SummaryTimer.next_summary(now)
      assert 1 == abs(now.minute - next_summary_time.minute)
    end

    test "should get the 2nd next summary time when the date is an summary interval date" do
      {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * * *"], [])
      next_date = SummaryTimer.next_summary(DateTime.utc_now())
      next_summary_time = SummaryTimer.next_summary(next_date)
      assert DateTime.compare(next_summary_time, next_date) == :gt
    end
  end

  property "previous_summaries/1 should retrieve the previous summary times from a date" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "* * * * * * *"], [])

    check all(previous_seconds <- StreamData.positive_integer()) do
      previous_summaries =
        SummaryTimer.previous_summaries(DateTime.utc_now() |> DateTime.add(-previous_seconds))

      assert length(previous_summaries) == previous_seconds
    end
  end

  test "previous_summary/1 should return the previous summary time" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "* * * * * * *"], [])

    assert ~U[2020-09-10 12:30:29Z] = SummaryTimer.previous_summary(~U[2020-09-10 12:30:30Z])
  end

  test "match_interval? check if a date match the summary timer interval" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * * *"], [])
    assert true == SummaryTimer.match_interval?(~U[2021-02-03 13:00:00Z])

    assert false == SummaryTimer.match_interval?(~U[2021-02-03 13:00:50Z])
  end

  property "next_summaries/1 should retrieve the next summary times from a date" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "* * * * * * *"], [])
    ref = DateTime.utc_now()

    check all(previous_seconds <- StreamData.positive_integer()) do
      next_summaries = SummaryTimer.next_summaries(DateTime.add(ref, -previous_seconds), ref)
      assert Enum.count(next_summaries) == previous_seconds
    end
  end
end
