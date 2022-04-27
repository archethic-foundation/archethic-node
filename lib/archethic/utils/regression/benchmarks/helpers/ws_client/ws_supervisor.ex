defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.WSSupervisor do
  @moduledoc """
    Supervisor for WS SubscriptionServer and WebSocket
  """
  use Supervisor
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.SubscriptionServer
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.WebSocket

  def start_link(args \\ %{}) do
    Supervisor.start_link(__MODULE__, args, name: :GQL_Client)
  end

  def init(args) do
    children = [
      {SubscriptionServer, args},
      {WebSocket, args}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
