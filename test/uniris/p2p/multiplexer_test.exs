defmodule Uniris.P2P.MultiplexerTest do
  use ExUnit.Case

  alias Uniris.P2P.Multiplexer

  import Mox

  setup :set_mox_global

  test "start_link/1 should create a multiplexer" do
    MockTransport
    |> expect(:read_from_socket, fn _, _, _, _ -> :ok end)

    {:ok, pid} =
      Multiplexer.start_link(
        socket: make_ref(),
        transport: MockTransport,
        recv_handler: fn _, _ -> :ok end
      )

    assert %{muxer_pid: _, demuxer_pid: _, transport: MockTransport} = :sys.get_state(pid)
  end

  describe "send_data/2" do
    test "should request the muxer to send and await demuxer to return data" do
      MockTransport
      |> expect(:read_from_socket, fn _, _fun, _, _ -> :ok end)
      |> expect(:send_message, fn _, _ -> :ok end)

      {:ok, pid} =
        Multiplexer.start_link(
          socket: make_ref(),
          transport: MockTransport,
          recv_handler: fn id, data, opts ->
            Multiplexer.notify_clients(Keyword.get(opts, :multiplexer_pid), id, data)
          end
        )

      spawn(fn -> Multiplexer.send_data(pid, "hello") end)
      Process.sleep(100)
      assert %{queue: %{1 => {_, _}}} = :sys.get_state(pid)
      Process.sleep(100)
      assert %{queue: %{}} = :sys.get_state(pid)
    end

    test "should return an error if timeout or closed is detected during the batch sending" do
      MockTransport
      |> expect(:read_from_socket, fn _, _fun, _, _ ->
        :skip
      end)
      |> expect(:send_message, fn _, _data -> {:error, :closed} end)

      {:ok, pid} =
        Multiplexer.start_link(
          socket: make_ref(),
          transport: MockTransport,
          recv_handler: fn id, data, opts ->
            Multiplexer.notify_clients(Keyword.get(opts, :multiplexer_pid), id, data)
          end
        )

      assert {:error, :closed} = Multiplexer.send_data(pid, "hello")
    end
  end
end
