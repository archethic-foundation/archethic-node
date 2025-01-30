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
  alias __MODULE__.SecurityParameters

  # Constants
  @scaling_limit 200
  @min_nodes 10
  # Maximum security parameters (for nodes >200)
  @max_malicious_rate 0.90
  @min_tolerance 1.0e-9
  # Minimum security parameters (for small networks)
  @min_malicious_rate 0.50
  @max_tolerance 1.0e-6

  defmodule SecurityParameters do
    @moduledoc """
    Security parameters for the hypergeometric distribution algorithm
    """
    defstruct [:malicious_rate, :tolerance, :overbooking_rate]

    @type t :: %__MODULE__{
            malicious_rate: float(),
            tolerance: float(),
            overbooking_rate: float()
          }
  end

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
  Returns the maximum security parameters
  """
  @spec get_max_security_parameters() :: SecurityParameters.t()
  def get_max_security_parameters() do
    %SecurityParameters{
      malicious_rate: @max_malicious_rate,
      tolerance: @min_tolerance,
      overbooking_rate: 0.0
    }
  end

  @doc """
  Returns the security parameters (malicious rate and tolerance) based on the number of nodes.
  Uses logarithmic scaling from 10 to 200 nodes
  """
  @spec get_security_parameters(nb_nodes :: integer()) ::
          {malicious_rate :: float(), tolerance :: float()}
  def get_security_parameters(nb_nodes) when nb_nodes >= @scaling_limit do
    %SecurityParameters{
      malicious_rate: @max_malicious_rate,
      tolerance: @min_tolerance,
      overbooking_rate: 0.0
    }
  end

  def get_security_parameters(nb_nodes) when nb_nodes <= @min_nodes do
    %SecurityParameters{
      malicious_rate: @min_malicious_rate,
      tolerance: @max_tolerance,
      overbooking_rate: 0.0
    }
  end

  def get_security_parameters(nb_nodes) do
    scale = :math.log(nb_nodes - @min_nodes) / :math.log(@scaling_limit - @min_nodes)
    scale = scale |> max(0) |> min(1)

    malicious_rate = @min_malicious_rate + (@max_malicious_rate - @min_malicious_rate) * scale

    log_min_tol = :math.log(@min_tolerance)
    log_max_tol = :math.log(@max_tolerance)
    log_tol = log_max_tol + (log_min_tol - log_max_tol) * scale
    tolerance = :math.exp(log_tol)

    %SecurityParameters{
      malicious_rate: malicious_rate,
      tolerance: tolerance,
      overbooking_rate: 0.0
    }
  end

  @doc """
  Execute the hypergeometric distribution simulation from a given number of nodes.

  Because the simulation can take time when its number if big such as 100 000, the previous results
  are stored in the GenServer state

  ## Examples

      iex> params = HypergeometricDistribution.get_max_security_parameters()
      ...> HypergeometricDistribution.run_simulation(5, params)
      {5, 0}

      iex> params = HypergeometricDistribution.get_max_security_parameters()
      ...> HypergeometricDistribution.run_simulation(20, params)
      {19, 0}

      iex> params = HypergeometricDistribution.get_max_security_parameters()
      ...> HypergeometricDistribution.run_simulation(40, params)
      {37, 0}

      iex> params = HypergeometricDistribution.get_max_security_parameters()
      ...> HypergeometricDistribution.run_simulation(100, params)
      {84, 0}

      iex> params = HypergeometricDistribution.get_max_security_parameters()
      ...> HypergeometricDistribution.run_simulation(1000, params)
      {178, 0}

      iex> params = HypergeometricDistribution.get_max_security_parameters()
      ...> HypergeometricDistribution.run_simulation(10000, params)
      {195, 0}

      iex> params =
      ...>   HypergeometricDistribution.get_security_parameters(5)
      ...>   |> Map.put(:overbooking_rate, 0.1)
      ...> 
      ...> HypergeometricDistribution.run_simulation(5, params)
      {3, 0}

      iex> params =
      ...>   HypergeometricDistribution.get_security_parameters(20)
      ...>   |> Map.put(:overbooking_rate, 0.1)
      ...> 
      ...> HypergeometricDistribution.run_simulation(20, params)
      {14, 1}

      iex> params =
      ...>   HypergeometricDistribution.get_security_parameters(40)
      ...>   |> Map.put(:overbooking_rate, 0.1)
      ...> 
      ...> HypergeometricDistribution.run_simulation(40, params)
      {31, 3}

      iex> params =
      ...>   HypergeometricDistribution.get_security_parameters(100)
      ...>   |> Map.put(:overbooking_rate, 0.1)
      ...> 
      ...> HypergeometricDistribution.run_simulation(100, params)
      {85, 9}

      iex> params =
      ...>   HypergeometricDistribution.get_security_parameters(1000)
      ...>   |> Map.put(:overbooking_rate, 0.05)
      ...> 
      ...> HypergeometricDistribution.run_simulation(1000, params)
      {527, 27}

      iex> params =
      ...>   HypergeometricDistribution.get_security_parameters(10000)
      ...>   |> Map.put(:overbooking_rate, 0.05)
      ...> 
      ...> HypergeometricDistribution.run_simulation(10000, params)
      {908, 47}
  """
  @spec run_simulation(nb_nodes :: pos_integer(), security_parameters :: SecurityParameters.t()) ::
          {required_validations :: pos_integer(), overbooking :: pos_integer()}
  def run_simulation(
        nb_nodes,
        security_parameters = %SecurityParameters{malicious_rate: malicious_rate}
      )
      when is_integer(nb_nodes) and nb_nodes > 0 do
    nb_malicious = trunc(nb_nodes * malicious_rate)
    nb_good = nb_nodes - nb_malicious

    cond do
      nb_good == 0 -> {nb_nodes, 0}
      nb_malicious == 0 -> {1, max(nb_nodes - 1, 3)}
      true -> do_run_simulation(nb_nodes, nb_malicious, nb_good, security_parameters)
    end
  end

  defp do_run_simulation(nb_nodes, nb_malicious, _, %SecurityParameters{
         tolerance: tolerance,
         overbooking_rate: overbooking_rate
       })
       when overbooking_rate == 0 do
    Enum.reduce_while(1..nb_nodes, {nb_nodes, 0}, fn n, acc ->
      cond do
        n > nb_malicious ->
          {:halt, {n, 0}}

        simple_probability_under_tolerance?(n, nb_malicious, nb_nodes, tolerance) ->
          {:halt, {n, 0}}

        true ->
          {:cont, acc}
      end
    end)
  end

  defp do_run_simulation(nb_nodes, nb_malicious, nb_good, %SecurityParameters{
         tolerance: tolerance,
         overbooking_rate: overbooking_rate
       }) do
    Enum.reduce_while(1..nb_nodes, {nb_nodes, 0}, fn n, acc ->
      nb_overbooked = trunc(n * overbooking_rate) |> min(nb_good)
      nb_max_malicious = n - nb_overbooked

      cond do
        nb_max_malicious > nb_malicious ->
          {:halt, {nb_max_malicious, nb_overbooked}}

        overbooked_probability_under_tolerance?(
          n,
          nb_max_malicious,
          nb_overbooked,
          nb_malicious,
          nb_good,
          nb_nodes,
          tolerance
        ) ->
          {:halt, {nb_max_malicious, nb_overbooked}}

        true ->
          {:cont, acc}
      end
    end)
  end

  defp simple_probability_under_tolerance?(n, nb_malicious, nb_nodes, tolerance) do
    log_malicious = log_binomial(nb_malicious, n)
    log_total = log_binomial(nb_nodes, n)
    p = :math.exp(log_malicious - log_total)
    p < tolerance
  end

  defp overbooked_probability_under_tolerance?(
         n,
         nb_max_malicious,
         nb_overbooked,
         nb_malicious,
         nb_good,
         nb_nodes,
         tolerance
       ) do
    log_mal = log_binomial(nb_malicious, nb_max_malicious)
    log_good = log_binomial(nb_good, nb_overbooked)
    log_total = log_binomial(nb_nodes, n)

    p = :math.exp(log_mal + log_good - log_total)

    cond do
      p >= tolerance ->
        false

      nb_overbooked < 1 ->
        true

      true ->
        # Calculate probability to have more malicious with same number of nodes
        log_mal_increased = log_binomial(nb_malicious, nb_max_malicious + 1)
        log_good_decreased = log_binomial(nb_good, nb_overbooked - 1)
        pn = :math.exp(log_mal_increased + log_good_decreased - log_total)

        # Probability to have more malicious node in the set must be lower
        pn < p
    end
  end

  defp log_binomial(n, k) when k < 0 or k > n, do: :error
  defp log_binomial(n, k) when k == 0 or k == n, do: 0

  defp log_binomial(n, k) do
    k = min(k, n - k)

    Enum.reduce(1..k, 0, fn i, acc ->
      acc + (:math.log(n - k + i) - :math.log(i))
    end)
  end
end
