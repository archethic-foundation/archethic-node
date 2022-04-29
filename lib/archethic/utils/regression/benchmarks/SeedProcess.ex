defmodule ArchEthic.Utils.Regression.Benchmark.SeedProcess do
  @moduledoc """
    Random seed and txn generator
  """
  use GenServer
  # alias ArchEthic.Utils.Regression.Benchmark.NodeThroughput
  # alias ArchEthic.Utils.WSClient

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(args) do
    # requires  seeds to be in args in format
    # [seeds: %{912 => {"sender_seed_A_912", "reciever_seed_B_912"}}]
    seeds = Keyword.get(args, :seeds)
    {:ok, _state = %{seeds: seeds}}
  end

  def get_state(pid) do
    :sys.get_state(pid)
  end

  def pop_seed(pid) do
    GenServer.call(pid, :pop)
  end

  def check_seed(pid, index) do
    GenServer.call(pid, {:check_seed, index})
  end

  @doc """
    Provides a random seed and index value
  """
  def handle_call(:pop, _from, state) do
    # get a list of seeds from  state.seeds
    # IO.inspect(Enum.count(state.seeds))
    seeds_index_list = Map.keys(state.seeds)
    # chooses a random element(seed index) from list
    index = Enum.random(seeds_index_list)
    # pop that index value to get corresponding seed value
    {poped_value, new_seed_map} = Map.pop(state.seeds, index)

    {:reply, {index, poped_value}, %{state | seeds: new_seed_map}}
  end

  # check existence of a seed
  def handle_call({:check_seed, index}, _from, state) do
    {:reply, Map.has_key?(state.seeds, index), state}
  end

  def put_seed(pid, index, taken_value) do
    GenServer.cast(pid, {:put, index, taken_value})
  end

  @doc """
    Put back the taken seed
  """
  def handle_cast({:put, index, taken_value}, state) do
    # put backs seed as
    # seeds: %{index => taken_value}
    {:noreply, %{state | seeds: Map.put(state.seeds, index, taken_value)}}
  end
end
