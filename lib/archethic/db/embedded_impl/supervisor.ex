defmodule Archethic.DB.EmbeddedImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.DB.EmbeddedImpl.BootstrapInfo
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.P2PView
  alias Archethic.DB.EmbeddedImpl.StatsInfo

  require Logger

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    path = Archethic.DB.EmbeddedImpl.db_path()
    Logger.info("Load database at #{path}")
    File.mkdir_p!(path)
    :ets.new(:archethic_db_chain_writers, [:named_table, :public])

    children = [
      {DynamicSupervisor,
       strategy: :one_for_one, name: Archethic.DB.EmbeddedImpl.ChainWriterSupervisor},
      {Task, fn -> initialize_chain_writers(path) end},
      {ChainIndex, path: path},
      # {ChainWriter, path: path},
      {BootstrapInfo, path: path},
      {P2PView, path: path},
      {StatsInfo, path: path}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp initialize_chain_writers(path) do
    Enum.each(1..20, fn i ->
      DynamicSupervisor.start_child(
        Archethic.DB.EmbeddedImpl.ChainWriterSupervisor,
        {ChainWriter, path: path, partition: i}
      )
    end)
  end
end
