defmodule ArchEthic.Utils.Regression.Helpers.WSClient2 do
  use WebSockex
  require Logger

  def start_link(state = %{}) do
    url = "localhost:4000/socket/websocket"
    WebSockex.start_link(url, __MODULE__, state)
  end

  @impl true
  def handle_connect(_conn, state) do
    WebSockex.cast(self(), {:send_message, ["1", "1", "__absinthe__:control", "phx_join", {}]})
    {:ok, state}
  end

  @impl true

  def handle_frame({:text, msg}, state) do
    IO.puts("Received a message: #{msg}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:send, {type, msg} = frame}, state) do
    IO.puts("Sending #{type} frame with payload: #{msg}")
    {:reply, frame, state}
  end
end
