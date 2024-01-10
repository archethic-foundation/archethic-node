defmodule Archethic.Election.HypergeometricDistribution do
  @moduledoc """
  Hypergeometric distribution has the property to guarantee than even with 90% of malicious nodes
  the risk that an honest cannot detect a fraudulent transaction is only 10^-9 or once chance in one billion.
  (beyond the standards of the acceptable risk for aviation or nuclear)

  Therefore it describes the probability of k success (detection of fraudulent operation) for `n`
  drawn (verifications) without repetition with a total finite number of nodes `N` and by
  considering a number N1 of malicious nodes (90%).

  No matter how many nodes are running on the network, a control with a tiny part of the network (less than 200 nodes)
  ensures the atomicity property of network transactions.
  """

  use GenServer
  @vsn 1

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    PubSub.register_to_node_update()

    {:ok, %{previous_simulations: %{}, clients: %{}, tasks: %{}}}
  end

  def handle_info(
        {:node_update, %Node{available?: true, authorized?: true}},
        state = %{tasks: tasks}
      ) do
    nb_nodes = length(P2P.authorized_and_available_nodes())

    case Map.get(tasks, nb_nodes) do
      nil ->
        %Task{ref: ref} = start_simulation_task(nb_nodes)
        {:noreply, Map.update!(state, :tasks, &Map.put(&1, nb_nodes, ref))}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:node_update, %Node{available?: false, authorized?: true}},
        state = %{tasks: tasks}
      ) do
    nb_nodes = length(P2P.authorized_and_available_nodes())

    case Map.get(tasks, nb_nodes) do
      nil ->
        %Task{ref: ref} = start_simulation_task(nb_nodes)
        {:noreply, Map.update!(state, :tasks, &Map.put(&1, nb_nodes, ref))}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:node_update, _}, state), do: {:noreply, state}

  def handle_info(
        {ref, {nb_nodes, simulation_result}},
        state = %{clients: clients}
      ) do
    clients
    |> Map.get(ref, [])
    |> Enum.each(&GenServer.reply(&1, simulation_result))

    new_state =
      state
      |> Map.update!(:previous_simulations, &Map.put(&1, nb_nodes, simulation_result))
      |> Map.update!(:tasks, &Map.delete(&1, nb_nodes))
      |> Map.update!(:clients, &Map.delete(&1, ref))

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  def handle_call(
        {:run_simulation, nb_nodes},
        from,
        state = %{previous_simulations: previous_simulations, tasks: tasks}
      )
      when is_integer(nb_nodes) and nb_nodes >= 0 do
    case Map.get(previous_simulations, nb_nodes) do
      nil ->
        case Map.get(tasks, nb_nodes) do
          nil ->
            %Task{ref: ref} = start_simulation_task(nb_nodes)

            new_state =
              state
              |> Map.update!(:clients, &Map.put(&1, ref, [from]))
              |> Map.update!(:tasks, &Map.put(&1, nb_nodes, ref))

            {:noreply, new_state}

          ref ->
            {:noreply, update_in(state, [:clients, Access.key(ref, [])], &[from | &1])}
        end

      simulation ->
        {:reply, simulation, state}
    end
  end

  defp start_simulation_task(nb_nodes) do
    Task.async(fn ->
      pid = Port.open({:spawn_executable, executable()}, args: [Integer.to_string(nb_nodes)])

      receive do
        {^pid, {:data, data}} ->
          {result, _} = :string.to_integer(data)
          {nb_nodes, result}
      end
    end)
  end

  defp executable do
    Application.app_dir(:archethic, "/priv/c_dist/hypergeometric_distribution")
  end

  @doc """
  Execute the hypergeometric distribution simulation from a given number of nodes.

  Because the simulation can take time when its number if big such as 100 000, the previous results
  are stored in the GenServer state

  ## Examples

      iex> HypergeometricDistribution.run_simulation(5)
      5

      iex> HypergeometricDistribution.run_simulation(20)
      19

      iex> HypergeometricDistribution.run_simulation(40)
      37

      iex> HypergeometricDistribution.run_simulation(100)
      84

      iex> HypergeometricDistribution.run_simulation(1000)
      178

      iex> HypergeometricDistribution.run_simulation(10000)
      195
  """
  @spec run_simulation(pos_integer) :: pos_integer
  def run_simulation(nb_nodes) when is_integer(nb_nodes) and nb_nodes > 0 and nb_nodes <= 10,
    do: nb_nodes

  def run_simulation(nb_nodes) when is_integer(nb_nodes) and nb_nodes > 0 do
    GenServer.call(__MODULE__, {:run_simulation, nb_nodes}, 60_000)
  end
end
