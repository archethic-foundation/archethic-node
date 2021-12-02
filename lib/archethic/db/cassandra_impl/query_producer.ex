defmodule ArchEthic.DB.CassandraImpl.QueryProducer do
  @moduledoc false

  use GenStage

  def start_link(args \\ []) do
    GenStage.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec add_query(query :: binary(), parameters :: list(), stream? :: boolean()) ::
          Enumerable.t() | :ok
  def add_query(query, parameters \\ [], stream \\ false)

  def add_query(query, parameters, false) do
    pid = :persistent_term.get(:cassandra_query_producer)
    GenStage.call(pid, {:call, query, parameters})
  end

  def add_query(query, parameters, true) do
    pid = :persistent_term.get(:cassandra_query_producer)

    Stream.resource(
      fn ->
        {:ok, ref} = GenStage.call(pid, {:streaming, query, parameters})
        ref
      end,
      fn ref ->
        receive do
          {:data, ^ref, data} ->
            {[data], ref}

          {:data_end, ^ref} ->
            {:halt, ref}
        end
      end,
      fn _ -> :ok end
    )
  end

  def init(_args) do
    :persistent_term.put(:cassandra_query_producer, self())
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  def handle_call({:call, query, parameters}, from, %{queue: queue, demand: demand}) do
    queue = :queue.in({query, :call, parameters, %{from: from}}, queue)
    dispatch_events(queue, demand, [])
  end

  def handle_call({:streaming, query, parameters}, from, %{queue: queue, demand: demand}) do
    ref = make_ref()
    queue = :queue.in({query, :streaming, parameters, %{from: from, ref: ref}}, queue)
    {_, events, state} = dispatch_events(queue, demand, [])

    {:reply, {:ok, ref}, events, state}
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
