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
    test "should request the muxer to prepare the sending of the data" do
      MockTransport
      |> expect(:read_from_socket, fn _, _fun, _, _ -> :ok end)

      {:ok, pid} =
        Multiplexer.start_link(
          socket: make_ref(),
          transport: MockTransport,
          recv_handler: fn responses, opts ->
            Multiplexer.notify_clients(Keyword.get(opts, :multiplexer_pid), responses)
          end,
          timeframe: 5_000
        )

      spawn(fn -> Multiplexer.send_data(pid, "hello") end)
      Process.sleep(100)
      assert %{next_id: 2, queue: %{1 => {_, _}}} = :sys.get_state(pid)
    end

    test "receive data in batch when the timeframe is reach and should notify clients" do
      MockTransport
      |> expect(:connect, fn _, _, _, _ -> {:ok, make_ref()} end)
      |> expect(:read_from_socket, fn _, fun, _, _ ->
        pid =
          spawn(fn ->
            receive do
              {:send, data} ->
                fun.(data)
            end
          end)

        :persistent_term.put(:registry, pid)
        :ok
      end)
      |> expect(:send_message, fn _, data ->
        send(:persistent_term.get(:registry), {:send, data})
        :ok
      end)

      {:ok, pid} =
        Multiplexer.start_link(
          socket: make_ref(),
          transport: MockTransport,
          recv_handler: fn responses, opts ->
            Multiplexer.notify_clients(Keyword.get(opts, :multiplexer_pid), responses)
          end
        )

      assert {:ok, "hello"} = Multiplexer.send_data(pid, "hello")
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
          recv_handler: fn responses, opts ->
            Multiplexer.notify_clients(Keyword.get(opts, :multiplexer_pid), responses)
          end
        )

      assert {:error, :closed} = Multiplexer.send_data(pid, "hello")
    end
  end
end
