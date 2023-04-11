defmodule Archethic.BeaconChain.Subset.StatsCollector do
  @moduledoc """
  Process responsible to collect subset network stats
  and reply to parallels requests to reduce the network load.
  """

  @vsn Mix.Project.config()[:version]
  use GenServer

  alias Archethic.BeaconChain.NetworkCoordinates

  require Logger

  def start_link(_arg \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get(DateTime.t()) :: Nx.Tensor.t()
  def get(summary_time) do
    try do
      GenServer.call(__MODULE__, {:get, summary_time})
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Fetching network stats take longer than 5s")
        Nx.tensor(0)
    end
  end

  def init(_) do
    {:ok, %{fetching_task: nil, clients: []}}
  end

  def handle_call({:get, summary_time}, from, state = %{fetching_task: nil}) do
    task = Task.async(fn -> NetworkCoordinates.fetch_network_stats(summary_time) end)

    new_state =
      state
      |> Map.update!(:clients, &[from | &1])
      |> Map.put(:fetching_task, task)

    {:noreply, new_state}
  end

  def handle_call({:get, _summary_time}, from, state = %{fetching_task: _}) do
    new_state =
      state
      |> Map.update!(:clients, &[from | &1])

    {:noreply, new_state}
  end

  def handle_info({ref, stats}, state = %{clients: clients, fetching_task: %Task{ref: ref_task}})
      when ref_task == ref do
    Enum.each(clients, &GenServer.reply(&1, stats))

    new_state =
      state
      |> Map.put(:clients, [])
      |> Map.put(:fetching_task, nil)

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}
end
