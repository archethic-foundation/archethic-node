defmodule Archethic.SelfRepair.NetworkChain do
  @moduledoc """
  Facade for the network chain synchronization
  """

  alias Archethic.SelfRepair.NetworkChainWorker

  @doc """
  Asynchronously sync the network chain of given type.
  Concurrent runs are discarded.
  """
  @spec resync(NetworkChainWorker.type()) :: :ok
  def resync(network_chain_type) do
    NetworkChainWorker.resync(network_chain_type)
  end

  @doc """
  Asynchronously sync the network chains of given types.
  Every sync is done in its own worker, where concurrent runs are discarded.
  """
  @spec resync_many(list(NetworkChainWorker.type())) :: :ok
  def resync_many(network_chain_types) do
    Enum.each(
      network_chain_types,
      &NetworkChainWorker.resync/1
    )
  end
end
