defmodule UnirisNetwork.Application do
  @moduledoc false

  require Logger

  use Application

  def start(_type, _args) do
    :ets.new(:node_store, [:named_table, :set, :public])
    :ets.new(:shared_secrets, [:named_table, :set, :public, read_concurrency: true])

    children = [
      {Task.Supervisor, name: UnirisNetwork.TaskSupervisor},
      {Registry, keys: :unique, name: UnirisNetwork.NodeRegistry},
      {Registry, keys: :unique, name: UnirisNetwork.ConnectionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisNetwork.NodeSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisNetwork.ConnectionSupervisor},
      UnirisNetwork.GeoPatch
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: UnirisNetwork.Supervisor)
  end
end
