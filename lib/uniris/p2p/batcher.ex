defmodule Uniris.P2P.Batcher do
  @moduledoc """
  Manage the sending of batched request within a timeframe by aggregating
  all the queued messages towards a node into a single request
  """

  use GenServer

  alias Uniris.P2P
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Node

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @spec add_broadcast_request(list(Node.t()), Message.t()) :: :ok
  def add_broadcast_request(nodes, request) do
    GenServer.cast(__MODULE__, {:add_broadcast_request, request, nodes})
  end

  @doc false
  def add_broadcast_request(pid, nodes, request) do
    GenServer.cast(pid, {:add_broadcast_request, request, nodes})
  end

  def request_first_reply(nodes, request) do
    GenServer.call(__MODULE__, {:add_first_reply_request, request, nodes, false}, 10_000)
  end

  @doc false
  def request_first_reply(pid, nodes, request) do
    GenServer.call(pid, {:add_first_reply_request, request, nodes, false}, 10_000)
  end

  def request_first_reply_with_ack(nodes, request) do
    GenServer.call(__MODULE__, {:add_first_reply_request, request, nodes, true}, 10_000)
  end

  def request_first_reply_with_ack(pid, nodes, request) do
    GenServer.call(pid, {:add_first_reply_request, request, nodes, true}, 10_000)
  end

  @spec init(Keyword.t()) ::
          {:ok,
           %{broadcast_queue: %{}, timeout: timeout(), first_reply_queue: %{}, timer: reference()}}
  def init(args) do
    timeout = Keyword.get(args, :timeout, 1000)
    timer = schedule_dispatch(timeout)

    {:ok, %{timeout: timeout, broadcast_queue: %{}, first_reply_queue: %{}, timer: timer}}
  end

  def handle_cast(
        {:add_broadcast_request, request, nodes},
        state = %{broadcast_queue: queue}
      ) do
    new_queue =
      Enum.reduce(nodes, queue, fn node, acc ->
        Map.update(acc, node, [request], &[request | &1])
      end)

    {:noreply, Map.put(state, :broadcast_queue, new_queue)}
  end

  def handle_call(
        {:add_first_reply_request, request, nodes, ack?},
        from,
        state = %{first_reply_queue: queue}
      ) do
    new_queue =
      Map.update(
        queue,
        request,
        {nodes, [{from, ack?}]},
        fn {nodes, froms} ->
          {nodes, [{from, ack?} | froms]}
        end
      )

    {:noreply, Map.put(state, :first_reply_queue, new_queue)}
  end

  def handle_info(
        :dispatch,
        state = %{
          timeout: timeout,
          broadcast_queue: broadcast_queue,
          first_reply_queue: first_reply_queue
        }
      ) do
    timer = schedule_dispatch(timeout)

    handle_broadcast_queue(broadcast_queue)
    handle_first_reply_queue(first_reply_queue)

    new_state =
      state
      |> Map.put(:broadcast_queue, %{})
      |> Map.put(:first_reply_queue, %{})
      |> Map.put(:timer, timer)

    {:noreply, new_state}
  end

  defp handle_broadcast_queue(queue) when map_size(queue) > 0 do
    Enum.each(queue, fn {node, requests} ->
      Task.start(fn ->
        P2P.send_message!(node, %BatchRequests{requests: requests})
      end)
    end)
  end

  defp handle_broadcast_queue(%{}), do: :ok

  defp handle_first_reply_queue(queue) when map_size(queue) > 0 do
    sorted_nodes_by_request =
      Enum.map(queue, fn {request, {nodes, from}} ->
        {request, {P2P.nearest_nodes(nodes), from}}
      end)
      |> Enum.into(%{})

    %{batch_by_nodes: batch_by_nodes, request_metadata: request_metadata} =
      group_request_by_first_node(sorted_nodes_by_request)

    Enum.each(batch_by_nodes, fn {node, batch_request} ->
      Task.start(fn -> first_reply_sending({node, batch_request}, request_metadata) end)
    end)
  end

  defp handle_first_reply_queue(%{}), do: :ok

  defp schedule_dispatch(timeout) do
    Process.send_after(self(), :dispatch, timeout)
  end

  defp group_request_by_first_node(nodes_by_request) do
    acc = %{batch_by_nodes: %{}, request_metadata: %{}}

    Enum.reduce(nodes_by_request, acc, fn {request, {[node | rest], from}}, acc ->
      acc
      |> put_in([:request_metadata, request], %{from: from, rest: rest})
      |> update_in(
        [:batch_by_nodes, Access.key(node, %BatchRequests{requests: []})],
        &Map.update!(&1, :requests, fn requests -> [request | requests] end)
      )
    end)
  end

  defp first_reply_sending(
         {node = %Node{}, batch_request = %BatchRequests{requests: requests}},
         request_metadata
       ) do
    case P2P.send_message(node, batch_request) do
      {:ok, %BatchResponses{responses: responses}} ->
        Enum.each(responses, &reply_response(&1, requests, request_metadata, node))

      {:error, reason} ->
        case determine_retry(requests, request_metadata) do
          {:error, :end_of_nodes} ->
            error_response(reason, requests, request_metadata)

          {:ok, batch_by_nodes, request_metadata} ->
            retry(batch_by_nodes, request_metadata)
        end
    end
  end

  defp reply_response({index, response}, requests, request_metadata, node) do
    request = Enum.at(requests, index)

    request_metadata
    |> get_in([request, :from])
    |> Enum.each(fn
      {from, true} ->
        GenServer.reply(from, {:ok, response, node})

      {from, false} ->
        GenServer.reply(from, {:ok, response})
    end)
  end

  defp determine_retry(requests, request_metadata) do
    filter_sorted_nodes_by_request =
      Enum.map(requests, fn request ->
        %{rest: rest, from: from} = Map.get(request_metadata, request)
        {request, {rest, from}}
      end)

    case group_request_by_first_node(filter_sorted_nodes_by_request) do
      %{batch_by_nodes: batch_by_nodes} when map_size(batch_by_nodes) == 0 ->
        {:error, :end_of_nodes}

      %{batch_by_nodes: batch_by_nodes, request_metadata: request_metadata} ->
        {:ok, batch_by_nodes, request_metadata}
    end
  end

  defp retry(batch_by_nodes, request_metadata) do
    Enum.each(batch_by_nodes, fn {node, batch_request} ->
      Task.start(fn -> first_reply_sending({node, batch_request}, request_metadata) end)
    end)
  end

  defp error_response(reason, requests, request_metadata) do
    requests
    |> Enum.map(&get_in(request_metadata, [&1, :from]))
    |> Enum.each(&GenServer.reply(elem(&1, 0), {:error, reason}))
  end
end
