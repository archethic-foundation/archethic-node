defmodule Archethic.BeaconChain.Update do
  @moduledoc false

  use GenServer

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.RegisterBeaconUpdates

  alias Archethic.TaskSupervisor

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Subscribe for Beacon update to a node if not already subscribed
  """
  @spec subscribe(list(Node.t()), binary()) :: :ok
  def subscribe(nodes, subset) do
    GenServer.cast(__MODULE__, {:subscribe, nodes, subset})
  end

  @doc """
  Unsubscribe for Beacon update to a node
  """
  @spec unsubscribe(binary()) :: :ok
  def unsubscribe(node_public_key) do
    GenServer.cast(__MODULE__, {:unsubscribe, node_public_key})
  end


  def init(_args) do
    {:ok, Map.new()}
  end

  def handle_cast({:subscribe, nodes, subset}, state) do
    nodes_to_subscribe =
      Enum.reject(nodes, fn %Node{first_public_key: public_key} ->
        Map.get(state, public_key, []) |> Enum.member?(subset)
      end)

    message = %RegisterBeaconUpdates{
      node_public_key: Crypto.first_node_public_key(),
      subset: subset
    }

    new_state =
      if Enum.empty?(nodes_to_subscribe) do
        state
      else
        Task.Supervisor.async_stream(
          TaskSupervisor,
          nodes_to_subscribe,
          fn node ->
            {P2P.send_message(node, message), node.first_public_key}
          end,
          ordered: false,
          on_timeout: :kill_task
        )
        |> Stream.filter(&match?({:ok, {{:ok, _}, _}}, &1))
        |> Stream.map(fn {:ok, {{:ok, _response}, public_key}} -> public_key end)
        |> Enum.reduce(state, fn public_key, acc ->
          Map.update(acc, public_key, [], fn subsets -> [subset | subsets] end)
        end)
      end

    {:noreply, new_state}
  end

  def handle_cast({:unsubscribe, node_public_key}, state) do
    new_state = Map.delete(state, node_public_key)

    {:noreply, new_state}
  end
end
