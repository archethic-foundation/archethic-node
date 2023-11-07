defmodule Archethic.Metrics.PollerTest do
  use ArchethicCase

  alias Archethic.Metrics.Poller
  alias Archethic.P2P
  alias Archethic.P2P.Node

  import Mox

  describe "When Archethic is up" do
    setup do
      :persistent_term.put(:archethic_up, :up)
    end

    test "start_link/1 should start the process starts a timer" do
      {:ok, pid} = Poller.start_link(interval: 10_000)

      assert %{
               timer: timer
             } = :sys.get_state(pid)

      Process.cancel_timer(timer)
    end

    test "monitor/0 should add the process to the list of subscribed process for updates" do
      {:ok, pid} = Poller.start_link(interval: 10_000)

      Poller.monitor(pid)

      assert %{pid_refs: pid_refs, timer: timer} = :sys.get_state(pid)
      me = self()

      assert Map.has_key?(pid_refs, me)

      Process.cancel_timer(timer)
    end

    test "when the monitored process dies the poller should deregister the process" do
      {:ok, pid} = Poller.start_link(interval: 10_000)

      child_pid =
        spawn(fn ->
          Poller.monitor(pid)
          Process.sleep(2_000)
        end)

      Process.sleep(200)
      assert %{pid_refs: pid_refs, timer: timer} = :sys.get_state(pid)
      assert Map.has_key?(pid_refs, child_pid)

      Process.cancel_timer(timer)

      Process.sleep(2_000)

      assert %{pid_refs: pid_refs} = :sys.get_state(pid)
      assert !Map.has_key?(pid_refs, child_pid)
    end

    test "when the timer is reached, `poll_metrics` is received to fetch the metrics" do
      node_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        http_port: 4000,
        first_public_key: node_public_key,
        last_public_key: node_public_key,
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockMetricsCollector
      |> stub(:fetch_metrics, fn _, _ ->
        {:ok,
         """
         # HELP archethic_mining_full_transaction_validation_duration
         # TYPE archethic_mining_full_transaction_validation_duration histogram
         archethic_mining_full_transaction_validation_duration_sum 9
         archethic_mining_full_transaction_validation_duration_count 50
         """}
      end)

      {:ok, pid} = Poller.start_link(interval: 1_000)
      Poller.monitor(pid)

      assert_receive {:update_data,
                      %{
                        "archethic_mining_full_transaction_validation_duration" => %{
                          sum: 9.0,
                          count: 50
                        }
                      }, ^node_public_key},
                     2_000
    end
  end
end
