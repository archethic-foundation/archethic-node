defmodule UnirisNetwork.P2P.Atomic do
  @moduledoc false

  alias UnirisNetwork.Node
  alias UnirisNetwork.P2P.Client

  @spec call(list(Node.t()), request :: binary()) ::
          {:ok, term(), list(Node.t())}
          | {:error, :consensus_not_reached}
          | {:error, reason :: atom()}
  def call(nodes, request) do
    Task.Supervisor.async_stream_nolink(
           UnirisNetwork.TaskSupervisor,
           nodes,
           &Client.send(&1, request)
         )
         |> Enum.filter(fn res -> match?({:ok, _}, res) end)
         |> reduce_response_atomically(%{nodes: [], data: nil})
       |> case do
      %{nodes: _nodes, data: {:error, reason}} ->
        {:error, reason}

      %{nodes: nodes, data: {:ok, data}} ->
        {:ok, data, nodes}

      :no_consensus ->
        {:error, :consensus_not_reached}
    end
  end

  @spec cast(list(Node.t()), request :: binary()) :: :ok | {:error, :network_issue}
  def cast(nodes, request) do
    Task.Supervisor.async_stream_nolink(UnirisNetwork.TaskSupervisor, nodes, &Client.send(&1, request))
    |> Enum.filter(fn res -> match?({:ok, _}, res) end)
    |> Enum.count(fn {:ok, res} -> match?({:ok, _}, res) end)
    |> case do
      n when n == length(nodes) ->
        :ok

      _ ->
        {:error, :network_issue}
    end
  end

  defp reduce_response_atomically(
         [{:ok, {:ok, result, node}} | rest],
         acc = %{data: prev_data, nodes: _}
       ) do
    cond do
      prev_data == nil ->
        acc = Map.put(acc, :data, result)

        acc =
          case result do
            {:ok, _} ->
              Map.put(acc, :nodes, [node])

            _ ->
              acc
          end

        reduce_response_atomically(rest, acc)

      acc.data != result ->
        :no_consensus

      true ->
        reduce_response_atomically(rest, Map.update!(acc, :nodes, &(&1 ++ [node])))
    end
  end

  defp reduce_response_atomically([], acc), do: acc
end
