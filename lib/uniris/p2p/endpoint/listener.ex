defmodule Uniris.P2P.Endpoint.Listener do
  @moduledoc false

  use GenServer

  require Logger

  alias Uniris.P2P.Connection
  alias Uniris.P2P.Transport

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    transport = Keyword.get(opts, :transport)
    port = Keyword.get(opts, :port)

    {:ok, listen_socket} = Transport.listen(transport, port, &handle_new_socket(&1, transport))

    Logger.info("P2P #{transport} Endpoint running on port #{port}")

    {:ok, %{listen_socket: listen_socket}}
  end

  defp handle_new_socket(socket, transport) do
    Connection.start_link(socket: socket, transport: transport, initiator?: false)
  end
end
