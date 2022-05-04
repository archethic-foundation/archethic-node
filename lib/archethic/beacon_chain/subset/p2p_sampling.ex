defmodule Archethic.BeaconChain.Subset.P2PSampling do
  @moduledoc false

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

  alias Archethic.TaskSupervisor

  @type p2p_view :: {available? :: boolean(), latency :: non_neg_integer()}

  @doc """
  Provide the list of nodes to sample for the given subset
  """
  @spec list_nodes_to_sample(binary(), list(Node.t())) :: list(Node.t())
  def list_nodes_to_sample(<<subset::8>>, node_list \\ P2P.list_nodes()) do
    node_list
    |> Enum.filter(fn %Node{first_public_key: <<_::8, _::8, first_digit::8, _::binary>>} ->
      first_digit == subset
    end)
    |> Enum.sort_by(& &1.first_public_key)
  end

  @doc """
  Get the p2p view for the given nodes while computing the bandwidth from the latency
  """
  @spec get_p2p_views(list(Node.t())) :: list(p2p_view())
  def get_p2p_views(nodes) when is_list(nodes) do
    Task.Supervisor.async_stream_nolink(TaskSupervisor, nodes, &do_sample_p2p_view/1,
      on_timeout: :kill_task,
      timeout: 2_000
    )
    |> Enum.map(fn
      {:ok, res} ->
        res

      {:exit, :timeout} ->
        {false, 1_000}

      {:error, _} ->
        {false, 0}
    end)
  end

  defp do_sample_p2p_view(node = %Node{}) do
    start_time = System.monotonic_time(:millisecond)

    case P2P.send_message(node, %Ping{}, 1_000) do
      {:ok, %Ok{}} ->
        end_time = System.monotonic_time(:millisecond)
        {true, end_time - start_time}

      {:error, _} ->
        {false, 1_000}
    end
  end
end
