defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.Subscriber do
  @moduledoc """
    GQL ABsinthe Subscription Abstraction provider.
  """
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.WSSupervisor
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.SubscriptionServer

  def start_ws_client(opts) do
    WSSupervisor.start_link(opts)
  end

  def absinthe_sub(query, variables, pid_or_callback, sub_id) do
    SubscriptionServer.subscribe(sub_id, pid_or_callback, query, variables)
  end
end
