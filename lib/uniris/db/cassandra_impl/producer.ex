defmodule Uniris.DB.CassandraImpl.Producer do
  @moduledoc false

  use GenStage

  def start_link(args \\ []) do
    GenStage.start_link(__MODULE__, args, name: __MODULE__)
  end

  def add_query(query, parameters \\ []) do
    GenStage.call(__MODULE__, {:add_query, query, parameters})
  end

  def init(_args) do
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  def handle_call({:add_query, query, parameters}, from, %{queue: queue, demand: demand}) do
    queue = :queue.in({query, parameters, from}, queue)
    dispatch_events(queue, demand, [])
  end

  def handle_demand(demand, %{queue: queue, demand: pending_demand}) do
    dispatch_events(queue, pending_demand + demand, [])
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), %{queue: queue, demand: 0}}
  end

  defp dispatch_events(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events])

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), %{queue: queue, demand: demand}}
    end
  end
end
