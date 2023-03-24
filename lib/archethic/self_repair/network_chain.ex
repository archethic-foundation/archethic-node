defmodule Archethic.SelfRepair.NetworkChain do
  @moduledoc """
  Facade for the network chain synchronization
  """

  alias Archethic.SelfRepair.NetworkChainWorker

  @doc """
  Synchronize the network chain of given type.
  Concurrent runs use the same worker.
  """
  @spec resync(NetworkChainWorker.type(), boolean()) :: :ok
  def resync(network_chain_type, async \\ true) do
    NetworkChainWorker.resync(network_chain_type, async)
  end

  @doc """
  Synchronize the network chains of given types.
  Every sync is done in its own worker, concurrent runs use the same worker.
  """
  @spec resync_many(list(NetworkChainWorker.type()), boolean()) :: :ok
  def resync_many(network_chain_types, async \\ true) do
    if async do
      # run all synch in parallel
      Enum.each(network_chain_types, &NetworkChainWorker.resync(&1, async))
    else
      # run all synch in parallel and then wait
      Task.Supervisor.async_stream_nolink(
        Archethic.TaskSupervisor,
        network_chain_types,
        &NetworkChainWorker.resync(&1, async),
        ordered: false,
        on_timeout: :kill_task,
        timeout: 5_000
      )
      |> Stream.run()
    end
  end
end
