defmodule ArchEthicWeb.TransactionSubscriber do
  @moduledoc false

  use GenServer

  alias Absinthe.Subscription
  alias ArchEthic.PubSub
  alias ArchEthicWeb.Endpoint

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    PubSub.register_to_new_transaction()
    {:ok, []}
  end

  def handle_info({:new_transaction, address}, state) when is_binary(address) do
    Subscription.publish(Endpoint, address,
      new_transaction: "*",
      acknowledge_storage: address
    )

    {:noreply, state}
  end

  def handle_info({:new_transaction, _, _, _}, state), do: {:noreply, state}
end
