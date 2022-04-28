defmodule ArchEthic.Utils.WSClient do
  @moduledoc """
    GQL ABsinthe Subscription Abstraction provider.
  """
  alias ArchEthic.Utils.WebSocket.WSSupervisor
  alias ArchEthic.Utils.WebSocket.SubscriptionServer

  def start_ws_client(opts) do
    WSSupervisor.start_link(opts)
  end

  def absinthe_sub(query, variables, pid_or_callback, sub_id) do
    SubscriptionServer.subscribe(sub_id, pid_or_callback, query, variables)
  end
end
