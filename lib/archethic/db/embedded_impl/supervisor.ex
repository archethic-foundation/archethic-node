defmodule Archethic.DB.EmbeddedImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.DB.EmbeddedImpl.BootstrapInfo
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.DB.EmbeddedImpl.ChainWriterSupervisor
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.P2PView
  alias Archethic.DB.EmbeddedImpl.StatsInfo

  alias ArchethicCache.LRU

  require Logger

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    path = Archethic.DB.EmbeddedImpl.filepath()
    ChainWriter.setup_folders!(path)

    children = [
      {PartitionSupervisor,
       child_spec: {ChainWriter, path: path}, name: ChainWriterSupervisor, partitions: 20},
      chain_index_cache(),
      {ChainIndex, path: path},
      {BootstrapInfo, path: path},
      {P2PView, path: path},
      {StatsInfo, path: path}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp chain_index_cache() do
    cache_max_size = Application.get_env(:archethic, Archethic.DB.ChainIndex.MaxCacheSize)

    %{
      id: :chain_index_cache,
      start:
        {LRU, :start_link,
         [
           :chain_index_cache,
           cache_max_size
         ]}
    }
  end
end
