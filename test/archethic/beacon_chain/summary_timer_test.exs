defmodule ArchEthic.BeaconChain.SummaryTimerTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ArchEthic.BeaconChain.SummaryTimer

  test "next_summary/2 should get the next summary time from a given date" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * * *"], [])
    now = ~U[2021-01-02 03:00:19Z]
    next_summary_time = SummaryTimer.next_summary(now)
    assert 1 == abs(now.minute - next_summary_time.minute)
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

    assert ~U[2021-02-03 13:07:37Z] =
             SummaryTimer.previous_summary(~U[2021-02-03 13:07:37.761481Z])
  end

  test "match_interval? check if a date match the summary timer interval" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * * *"], [])
    assert true == SummaryTimer.match_interval?(~U[2021-02-03 13:00:00Z])

    assert false == SummaryTimer.match_interval?(~U[2021-02-03 13:00:50Z])
  end

  property "next_summaries/1 should retrieve the next summary times from a date" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "* * * * * * *"], [])
    ref = DateTime.utc_now() |> DateTime.truncate(:second)

    check all(previous_seconds <- StreamData.positive_integer()) do
      next_summaries = SummaryTimer.next_summaries(DateTime.add(ref, -previous_seconds), ref)
      assert Enum.count(next_summaries) == previous_seconds
    end
  end
end
