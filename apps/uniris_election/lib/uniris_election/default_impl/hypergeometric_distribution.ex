defmodule UnirisElection.DefaultImpl.HypergeometricDistribution do
  @moduledoc false

  # Hypergeometric distribution has the property to garantee than even with 90% of malicious nodes
  # the risk that an honest cannot detect a fraudulent transaction is only 10^-9 or once chance in one billion.
  # (beyond the standards of the acceptable risk for aviation or nuclear)

  # Therefore it describes the probability of k success (detection of fraudulent operation) for `n`
  # drawn (verifications) without repetition with a total finite number of nodes `N` and by
  # considering a number N1 of malicious nodes (90%).

  # No matter how many nodes are running on the network, a control with a tiny part of the network (less than 200 nodes)
  # ensures the atomicity property of network transactions.

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(executable: executable) when is_binary(executable) do
    {:ok, %{executable: executable, previous_simulations: %{}}}
  end

  def handle_call(
        {:run_simulation, nb_nodes},
        _from,
        state = %{executable: executable, previous_simulations: previous_simulations}
      )
      when is_integer(nb_nodes) and nb_nodes >= 0 do
    case Map.get(previous_simulations, nb_nodes) do
      nil ->
        pid = Port.open({:spawn_executable, executable}, args: [Integer.to_string(nb_nodes)])

        receive do
          {^pid, {:data, data}} ->
            {n, _} = :string.to_integer(data)
            {:reply, n, put_in(state, [:previous_simulations, nb_nodes], n)}
        end

      simulation ->
        {:reply, simulation, state}
    end
  end

  @doc """
  Execute the hypergeometric distribution simulation from a given number of nodes.

  Because the simulation can take time when its number if big such as 100 000, the previous results
  are stored in the GenServer state

  ## Examples

      iex> UnirisElection.DefaultImpl.HypergeometricDistribution.run_simulation(100)
      84

      iex> UnirisElection.DefaultImpl.HypergeometricDistribution.run_simulation(1000)
      178

      iex> UnirisElection.DefaultImpl.HypergeometricDistribution.run_simulation(10000)
      195
  """
  @spec run_simulation(pos_integer) :: pos_integer
  def run_simulation(nb_nodes) when is_integer(nb_nodes) and nb_nodes > 0 do
    GenServer.call(__MODULE__, {:run_simulation, nb_nodes}, 60000)
  end
end
