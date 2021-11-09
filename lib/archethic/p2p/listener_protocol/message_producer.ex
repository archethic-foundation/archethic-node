defmodule ArchEthic.P2P.ListenerProtocol.MessageProducer do
  @moduledoc false
  use GenStage

  alias ArchEthic.P2P.ListenerProtocol.MessageProducerRegistry

  def start_link(arg) do
    GenStage.start_link(__MODULE__, arg)
  end

  def new_message(pid, message) do
    GenStage.cast(pid, {:new_message, message})
  end

  def init(arg) do
    socket = Keyword.get(arg, :socket)
    Registry.register(MessageProducerRegistry, socket, [])
    {:producer, %{demand: 0, queue: :queue.new()}}
  end

  def handle_cast({:new_message, message}, state = %{queue: queue, demand: pending_demand}) do
    queue = :queue.in(message, queue)
    dispatch_events(queue, pending_demand, [], state)
  end

  def handle_demand(incoming_demand, state = %{queue: queue, demand: pending_demand}) do
    dispatch_events(queue, incoming_demand + pending_demand, [], state)
  end

  defp dispatch_events(queue, 0, events, state) do
    {:noreply, Enum.reverse(events), %{state | queue: queue, demand: 0}}
  end

  defp dispatch_events(queue, demand, events, state) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events], state)

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), %{state | queue: queue, demand: demand}}
    end
  end
end
