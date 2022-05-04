defmodule Archethic.Utils.WebSocket.Supervisor do
  @moduledoc """
    Supervisor for WS SubscriptionServer and WebSocket
  """
  use Supervisor
  alias Archethic.Utils.WebSocket.SocketHandler

  def start_link(args \\ %{}) do
    Supervisor.start_link(__MODULE__, args, name: :GQL_Client)
  end

  def init(args) do
    children = [
      {SocketHandler, args}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
