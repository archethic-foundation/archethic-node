defmodule Uniris.P2P.Multiplexer.MuxerTest do
  use ExUnit.Case

  alias Uniris.P2P.Multiplexer.Muxer

  import Mox

  setup :set_mox_global

  test "start_link/1 should spawn a muxer process" do
    {:ok, pid} = Muxer.start_link(socket: make_ref(), transport: MockTransport)
    %{stream_id: 1} = :sys.get_state(pid)
  end

  describe "send_data/2" do
    test "should send the data and return stream id" do
      {:ok, pid} = Muxer.start_link(socket: make_ref(), transport: MockTransport)

      MockTransport
      |> stub(:send_message, fn _, _ ->
        :ok
      end)

      assert {:ok, 1} = Muxer.send_data(pid, "hello1")
      assert {:ok, 2} = Muxer.send_data(pid, "hello2")
      assert {:ok, 3} = Muxer.send_data(pid, "hello3")
    end
  end
end
