defmodule ArchEthic.Utils.WebSocket.WSSupervisor do
  @moduledoc """
    Supervisor for WS SubscriptionServer and WebSocket
  """
  use Supervisor
  alias ArchEthic.Utils.WebSocket.SubscriptionServer
  alias ArchEthic.Utils.WebSocket.WebSocketHandler

  def start_link(args \\ %{}) do
    Supervisor.start_link(__MODULE__, args, name: :GQL_Client)
  end

  def init(args) do
    children = [
      {SubscriptionServer, args},
      {WebSocketHandler, args}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
