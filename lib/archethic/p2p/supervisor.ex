defmodule Archethic.P2P.Supervisor do
  @moduledoc false

  alias Archethic.P2P.Client.ConnectionRegistry
  alias Archethic.P2P.Client.ConnectionSupervisor
  alias Archethic.P2P.MemTable
  alias Archethic.P2P.MemTableLoader
  alias Archethic.P2P.GeoPatch.GeoIP.MaxMindDB

  alias Archethic.Utils

  use Supervisor

  @table_name :connection_status

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.P2PSupervisor)
  end

  def init(_args) do
    # Start an ets table to manage node connection status.
    # This reduce the number of message sent to the Connection GenServer
    if :ets.whereis(@table_name) == :undefined do
      # Create ets table only if it doesn't exist (init of supervisor called in hot reload)
      :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    end

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
