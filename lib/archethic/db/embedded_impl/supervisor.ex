defmodule Archethic.DB.EmbeddedImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.DB.EmbeddedImpl.BootstrapInfo
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.P2PView
  alias Archethic.DB.EmbeddedImpl.StatsInfo

  alias ArchethicCache.LRU

  require Logger

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    path = Archethic.DB.EmbeddedImpl.db_path()
    Logger.info("Load database at #{path}")
    File.mkdir_p!(path)
    :ets.new(:archethic_db_chain_writers, [:named_table, :public])

    DynamicSupervisor.start_link(
      strategy: :one_for_one,
      name: Archethic.DB.EmbeddedImpl.ChainWriterSupervisor
    )

    initialize_chain_writers(path)

    children = [
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

  defp initialize_chain_writers(path) do
    Enum.each(0..19, fn i ->
      DynamicSupervisor.start_child(
        Archethic.DB.EmbeddedImpl.ChainWriterSupervisor,
        {ChainWriter, path: path, partition: i}
      )
    end)
  end
end
