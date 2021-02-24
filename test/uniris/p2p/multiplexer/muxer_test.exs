defmodule Uniris.P2P.Multiplexer.MuxerTest do
  use ExUnit.Case

  alias Uniris.P2P.Multiplexer.Muxer

  test "start_link/1 should spawn a muxer process" do
    {:ok, pid} = Muxer.start_link(timeframe: 50, multiplexer_pid: self())
    %{multiplexer_pid: _, messages: [], stream_id: 1} = :sys.get_state(pid)
  end

  describe "send_data/2" do
    test "should queue the data before the timeframe window" do
      {:ok, pid} = Muxer.start_link(timeframe: 1_000, multiplexer_pid: self())
      Muxer.send_data(pid, "hello1")
      Muxer.send_data(pid, "hello2")
      Muxer.send_data(pid, "hello3")

      assert %{messages: ["hello3", "hello2", "hello1"]} = :sys.get_state(pid)
    end

    test "should trigger the batch sending after the timeframe window" do
      {:ok, pid} = Muxer.start_link(timeframe: 50, multiplexer_pid: self())
      Muxer.send_data(pid, <<1::32, "hello1">>)
      Muxer.send_data(pid, <<2::32, "hello2">>)
      Muxer.send_data(pid, <<3::32, "hello3">>)

      assert_receive {:batch_sending,
                      <<1::8, 3::32, 3::32, 6::32, "hello3", 2::32, 6::32, "hello2", 1::32, 6::32,
                        "hello1">>}
    end
  end
end
