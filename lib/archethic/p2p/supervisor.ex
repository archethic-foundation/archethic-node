defmodule Archethic.P2P.Supervisor do
  @moduledoc false

  alias Archethic.P2P.Client.ConnectionRegistry
  alias Archethic.P2P.Client.ConnectionSupervisor
  alias Archethic.P2P.MemTable
  alias Archethic.P2P.MemTableLoader
  alias Archethic.P2P.GeoPatch.GeoIP.MaxMindDB

  alias Archethic.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.P2PSupervisor)
  end

  def init(_args) do
    optional_children = [
      {Registry, name: ConnectionRegistry, keys: :unique},
      ConnectionSupervisor,
      MaxMindDB,
      MemTable,
      MemTableLoader
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
