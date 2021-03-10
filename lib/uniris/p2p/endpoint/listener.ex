defmodule Uniris.P2P.Endpoint.Listener do
  @moduledoc false

  use GenServer

  require Logger

  alias Uniris.P2P.Endpoint.ConnectionSupervisor
  alias Uniris.P2P.Message
  alias Uniris.P2P.Multiplexer
  alias Uniris.P2P.Multiplexer.Muxer
  alias Uniris.P2P.Transport

  alias Uniris.Utils

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    transport = Keyword.get(opts, :transport)
    port = Keyword.get(opts, :port)

    {:ok, listen_socket} = Transport.listen(transport, port)

    Logger.info("P2P #{transport} Endpoint running on port #{port}")

    {:ok, %{listen_socket: listen_socket}}
  end

  def handle_new_connection(socket) do
    Task.Supervisor.start_child(ConnectionSupervisor, fn ->
      {:ok, _multiplexer_pid} =
        Multiplexer.start_link(
          socket: socket,
          transport: :tcp,
          recv_handler: &handle_requests/3
        )
    end)
  end

  defp handle_requests(id, data, opts) do
    muxer_pid = Keyword.get(opts, :muxer_pid)
    {data, _} = Message.decode(data)

    response =
      data
      |> Message.process()
      |> Message.encode()
      |> Utils.wrap_binary()

    Muxer.send_data(muxer_pid, id, response)
  end
end
