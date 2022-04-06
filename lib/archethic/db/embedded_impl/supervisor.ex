defmodule ArchEthic.DB.EmbeddedImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.DB.EmbeddedImpl.BootstrapInfo
  alias ArchEthic.DB.EmbeddedImpl.ChainWriter
  alias ArchEthic.DB.EmbeddedImpl.ChainIndex
  alias ArchEthic.DB.EmbeddedImpl.P2PView
  alias ArchEthic.DB.EmbeddedImpl.StatsInfo

  require Logger

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    path = ArchEthic.DB.EmbeddedImpl.db_path()
    Logger.info("Load database at #{path}")
    File.mkdir_p!(path)

    children = [
      {ChainIndex, path: path},
      {ChainWriter, path: path},
      {BootstrapInfo, path: path},
      {P2PView, path: path},
      {StatsInfo, path: path}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
