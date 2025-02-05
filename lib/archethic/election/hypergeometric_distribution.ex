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

  alias __MODULE__.SecurityParameters

  # Constants
  @storage_malicious_rate 0.9
  @storage_tolerance 1.0e-9
  @scaling_limit 200
  @min_nodes 10
  @max_overbooked_nodes 20
  # Maximum security parameters (for nodes >200)
  @max_malicious_rate 0.75
  @min_tolerance 1.0e-9
  @min_overbooking_rate 0.10
  # Minimum security parameters (for small networks)
  @min_malicious_rate 0.65
  @max_tolerance 1.0e-6
  @max_overbooking_rate 0.25

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

  @doc """
  Returns the storage security parameters
  """
  @spec get_storage_security_parameters() :: SecurityParameters.t()
  def get_storage_security_parameters() do
    %SecurityParameters{
      malicious_rate: @storage_malicious_rate,
      tolerance: @storage_tolerance,
      overbooking_rate: 0.0
    }
  end

  @doc """
  Returns the security parameters (malicious rate and tolerance) based on the number of nodes.
  Uses logarithmic scaling from 10 to 200 nodes for malicious rate and tolerance
  Uses linear scaling from 10 to 200 nodes for overbooking rate
  """
  @spec get_security_parameters(nb_nodes :: non_neg_integer()) :: SecurityParameters.t()
  def get_security_parameters(nb_nodes) when nb_nodes >= @scaling_limit do
    %SecurityParameters{
      malicious_rate: @max_malicious_rate,
      tolerance: @min_tolerance,
      overbooking_rate: @min_overbooking_rate
    }
  end

  def get_security_parameters(nb_nodes) when nb_nodes <= @min_nodes do
    %SecurityParameters{
      malicious_rate: @min_malicious_rate,
      tolerance: @max_tolerance,
      overbooking_rate: @max_overbooking_rate
    }
  end

  def get_security_parameters(nb_nodes) do
    log_scale = :math.log(nb_nodes - @min_nodes) / :math.log(@scaling_limit - @min_nodes)
    log_scale = log_scale |> max(0) |> min(1)

    malicious_rate = @min_malicious_rate + (@max_malicious_rate - @min_malicious_rate) * log_scale

    log_min_tol = :math.log(@min_tolerance)
    log_max_tol = :math.log(@max_tolerance)
    log_tol = log_max_tol + (log_min_tol - log_max_tol) * log_scale
    tolerance = :math.exp(log_tol)

    lin_scale = (nb_nodes - @min_nodes) / (@scaling_limit - @min_nodes)
    lin_scale = lin_scale |> max(0) |> min(1)

    log_min_over = :math.log(@min_overbooking_rate)
    log_max_over = :math.log(@max_overbooking_rate)
    log_over = log_max_over + (log_min_over - log_max_over) * lin_scale
    overbooking_rate = :math.exp(log_over)

    %SecurityParameters{
      malicious_rate: malicious_rate,
      tolerance: tolerance,
      overbooking_rate: overbooking_rate
    }
  end

  @doc """
  Execute the hypergeometric distribution simulation from a given number of nodes.

  Because the simulation can take time when its number if big such as 100 000, the previous results
  are stored in the GenServer state

  ## Examples

      iex> params = HypergeometricDistribution.get_storage_security_parameters()
      ...> HypergeometricDistribution.run_simulation(5, params)
      {5, 0}

      iex> params = HypergeometricDistribution.get_storage_security_parameters()
      ...> HypergeometricDistribution.run_simulation(20, params)
      {19, 0}

      iex> params = HypergeometricDistribution.get_storage_security_parameters()
      ...> HypergeometricDistribution.run_simulation(40, params)
      {37, 0}

      iex> params = HypergeometricDistribution.get_storage_security_parameters()
      ...> HypergeometricDistribution.run_simulation(100, params)
      {84, 0}

      iex> params = HypergeometricDistribution.get_storage_security_parameters()
      ...> HypergeometricDistribution.run_simulation(1000, params)
      {178, 0}

      iex> params = HypergeometricDistribution.get_storage_security_parameters()
      ...> HypergeometricDistribution.run_simulation(10000, params)
      {195, 0}

      iex> params = HypergeometricDistribution.get_security_parameters(5)
      ...> HypergeometricDistribution.run_simulation(5, params)
      {4, 1}

      iex> params = HypergeometricDistribution.get_security_parameters(20)
      ...> HypergeometricDistribution.run_simulation(20, params)
      {14, 4}

      iex> params = HypergeometricDistribution.get_security_parameters(40)
      ...> HypergeometricDistribution.run_simulation(40, params)
      {29, 7}

      iex> params = HypergeometricDistribution.get_security_parameters(100)
      ...> HypergeometricDistribution.run_simulation(100, params)
      {73, 13}

      iex> params = HypergeometricDistribution.get_security_parameters(1000)
      ...> HypergeometricDistribution.run_simulation(1000, params)
      {180, 19}

      iex> params = HypergeometricDistribution.get_security_parameters(10000)
      ...> HypergeometricDistribution.run_simulation(10000, params)
      {199, 20}
  """
  @spec run_simulation(nb_nodes :: pos_integer(), security_parameters :: SecurityParameters.t()) ::
          {required_validations :: pos_integer(), overbooking :: non_neg_integer()}
  def run_simulation(
        nb_nodes,
        security_parameters = %SecurityParameters{malicious_rate: malicious_rate}
      )
      when is_integer(nb_nodes) and nb_nodes > 0 do
    nb_malicious = trunc(nb_nodes * malicious_rate)
    nb_honest = nb_nodes - nb_malicious

    cond do
      nb_honest == 0 -> {nb_nodes, 0}
      nb_malicious == 0 -> {1, min(nb_nodes - 1, 3)}
      true -> do_run_simulation(nb_nodes, nb_malicious, nb_honest, security_parameters)
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

  defp do_run_simulation(nb_nodes, nb_malicious, nb_honest, %SecurityParameters{
         tolerance: tolerance,
         overbooking_rate: overbooking_rate
       }) do
    Enum.reduce_while(1..nb_nodes, {nb_nodes, 0}, fn n, acc ->
      # All overbooked nodes have to be honest
      nb_overbooked = trunc(n * overbooking_rate) |> min(nb_honest) |> min(@max_overbooked_nodes)
      nb_max_malicious = n - nb_overbooked

      cond do
        nb_max_malicious > nb_malicious ->
          {:halt, {nb_max_malicious, nb_overbooked}}

        overbooked_probability_under_tolerance?(
          n,
          nb_max_malicious,
          nb_overbooked,
          nb_malicious,
          nb_honest,
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
         nb_honest,
         nb_nodes,
         tolerance
       ) do
    log_mal = log_binomial(nb_malicious, nb_max_malicious)
    log_honest = log_binomial(nb_honest, nb_overbooked)
    log_total = log_binomial(nb_nodes, n)

    p = :math.exp(log_mal + log_honest - log_total)

    cond do
      p >= tolerance ->
        false

      nb_overbooked < 1 or nb_max_malicious == nb_malicious ->
        true

      true ->
        # Calculate probability to have more malicious with same number of nodes
        log_mal_increased = log_binomial(nb_malicious, nb_max_malicious + 1)
        log_honest_decreased = log_binomial(nb_honest, nb_overbooked - 1)
        pn = :math.exp(log_mal_increased + log_honest_decreased - log_total)

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
