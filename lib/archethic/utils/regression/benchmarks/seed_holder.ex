defmodule Archethic.Utils.Regression.Benchmark.SeedHolder do
  @moduledoc false
  use GenServer
  @vsn 1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(args) do
    seeds = Keyword.fetch!(args, :seeds)
    state = Enum.map(seeds, fn seed -> {seed, 0} end) |> Enum.into(%{})
    {:ok, state}
  end

  def get_seeds(pid) do
    GenServer.call(pid, :get_seeds)
  end

  def get_random_seed(pid) do
    GenServer.call(pid, :get_random_seed)
  end

  def pop_seed(pid) do
    GenServer.call(pid, :pop)
  end

  def handle_call(:get_seeds, _from, state) do
    {:reply, Map.keys(state), state}
  end

  @doc """
  Provides a random seed and index value
  """
  def handle_call(:pop, _from, state) do
    seeds_list = Map.keys(state)
    # chooses a random element(seed index) from list
    seed = Enum.random(seeds_list)
    # pop that index value to get corresponding seed value
    {index, new_seeds} = Map.pop(state, seed)

    {:reply, {seed, index}, new_seeds}
  end

  def handle_call(:get_random_seed, _from, state) do
    seed_list = Map.keys(state)
    seed = Enum.random(seed_list)
    {:reply, seed, state}
  end

  def put_seed(pid, seed, index) do
    GenServer.cast(pid, {:put, seed, index})
  end

  @doc """
  Put back the taken seed
  """
  def handle_cast({:put, seed, index}, state) do
    {:noreply, Map.put(state, seed, index + 1)}
  end
end
