defmodule Archethic.BeaconChain.Subset.P2PSampling do
  @moduledoc false

  alias Archethic.BeaconChain.SlotTimer

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Client
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

  @type p2p_view :: {availability_time :: non_neg_integer(), latency :: non_neg_integer()}

  @sample_timeout 1000

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
  @spec get_p2p_views(nodes :: list(Node.t())) :: list(p2p_view())
  def get_p2p_views(nodes = [_ | _]) do
    node_key = Crypto.first_node_public_key()

    Task.Supervisor.async_stream_nolink(
      Archethic.task_supervisors(),
      nodes,
      &do_sample_p2p_view(&1, node_key),
      on_timeout: :kill_task,
      max_concurrency: length(nodes)
    )
    |> Enum.map(fn
      {:ok, p2p_view} -> p2p_view
      {:exit, :timeout} -> {0, 0}
    end)
  end

  def get_p2p_views(_), do: []

  defp do_sample_p2p_view(node = %Node{first_public_key: first_public_key}, node_key) do
    start_time = System.monotonic_time(:millisecond)

    latency =
      case P2P.send_message(node, %Ping{}, @sample_timeout) do
        {:ok, %Ok{}} -> System.monotonic_time(:millisecond) - start_time
        {:error, _} -> 0
      end

    availability_time =
      if node_key == first_public_key,
        do: SlotTimer.get_time_interval(),
        else: Client.get_availability_timer(first_public_key, true)

    {availability_time, latency}
  end
end
