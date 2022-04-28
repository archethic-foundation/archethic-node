defmodule ArchEthic.Utils.WebSocket.SubscriptionServer do
  @moduledoc "
    Genserver that handles subscription logic.
  "
  use GenServer
  require Logger
  alias ArchEthic.Utils.WebSocket.WebSocketHandler

  def start_link(opts) do
    name = Keyword.get(opts, :ss_name, __MODULE__)

    state = %{
      socket: WebSocketHandler,
      subscriptions: %{}
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  def init(state) do
    {:ok, state}
  end

  def subscribe(local_subscription_id, callback_or_dest, query, variables \\ []) do
    GenServer.cast(
      __MODULE__,
      {:subscribe, local_subscription_id, callback_or_dest, query, variables}
    )
  end

  def handle_cast(
        {:subscribe, local_subscription_id, callback_or_dest, query, variables},
        state = %{socket: socket, subscriptions: subscriptions}
      ) do
    WebSocketHandler.subscribe(socket, self(), local_subscription_id, query, variables)

    callbacks = Map.get(subscriptions, local_subscription_id, [])
    subscriptions = Map.put(subscriptions, local_subscription_id, [callback_or_dest | callbacks])
    state = Map.put(state, :subscriptions, subscriptions)

    {:noreply, state}
  end

  # Incoming Notifications (from WSClient.WebSocketHandler)
  def handle_cast(
        {:subscription, local_subscription_id, response},
        state = %{subscriptions: subscriptions}
      ) do
    subscriptions
    |> Map.get(local_subscription_id, [])
    |> Enum.each(fn callback_or_dest -> handle_callback_or_dest(callback_or_dest, response) end)

    {:noreply, state}
  end

  def handle_cast({:joined}, state) do
    {:noreply, state}
  end

  defp handle_callback_or_dest(callback_or_dest, response) do
    if is_function(callback_or_dest) do
      callback_or_dest.(response)
    else
      send(callback_or_dest, response)
    end
  end
end
