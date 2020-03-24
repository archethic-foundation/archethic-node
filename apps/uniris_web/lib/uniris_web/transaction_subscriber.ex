defmodule UnirisWeb.TransactionSubscriber do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    UnirisSync.register_to_new_transaction()
    {:ok, []}
  end

  def handle_info({:new_transaction, address}, state) do
    Absinthe.Subscription.publish(UnirisWeb.Endpoint, address,
      new_transaction: "*"
    )
    {:noreply, state}
  end
end
