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

    case GenStage.call(pid, {:query, query, parameters, []}) do
      page = %Xandra.Page{} ->
        Enum.to_list(page)

      _ ->
        :ok
    end
  end

  def add_query(query, parameters, true) do
    Stream.resource(
      fn ->
        pid = :persistent_term.get(:cassandra_query_producer)
        {pid, %{options: [], status: :new}}
      end,
      fn
        {producer_pid, %{status: :done}} ->
          {:halt, producer_pid}

        {producer_pid, stream_state = %{options: options}} ->
          case GenStage.call(
                 producer_pid,
                 {:query, query, parameters, options}
               ) do
            page = %Xandra.Page{paging_state: nil} ->
              {Enum.to_list(page), {producer_pid, %{stream_state | status: :done}}}

            page = %Xandra.Page{paging_state: paging_state} ->
              opts = Keyword.put(options, :paging_state, paging_state)
              {Enum.to_list(page), {producer_pid, %{stream_state | options: opts}}}
          end
      end,
      fn _ -> :ok end
    )
  end

  def init(_args) do
    :persistent_term.put(:cassandra_query_producer, self())
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  def handle_call({:query, query, parameters, opts}, from, %{queue: queue, demand: demand}) do
    queue = :queue.in({query, parameters, from, opts}, queue)
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
