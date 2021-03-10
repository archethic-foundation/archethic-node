defmodule Uniris.P2P.Multiplexer.DemuxerTest do
  use ExUnit.Case

  alias Uniris.P2P.Multiplexer.Demuxer

  import Mox

  setup :set_mox_global

  test "start_link/1 should start a process to wait incoming message and demultiplex received data" do
    me = self()

    recv_handler = fn id, data, _ -> send(me, {:responses, id, data}) end

    MockTransport
    |> expect(:read_from_socket, fn _, fun, _, _ ->
      fun.(<<1::32, "hello">>)
    end)

    Demuxer.start_link(
      transport: MockTransport,
      socket: make_ref(),
      muxer_pid: self(),
      multiplexer_pid: self(),
      recv_handler: recv_handler
    )

    assert_receive {:responses, 1, "hello"}
  end
end
