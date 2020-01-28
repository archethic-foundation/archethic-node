defmodule UnirisNetwork.Application do
  @moduledoc false

  require Logger

  use Application

  def start(_type, _args) do

    port = Application.get_env(:uniris_network, :port)
    :ets.new(:node_store, [:named_table, :set, :public])
    :ets.new(:shared_secrets, [:named_table, :set, :public, read_concurrency: true])

    children = [
      {Task.Supervisor, name: UnirisNetwork.TaskSupervisor},
      {Registry, keys: :unique, name: UnirisNetwork.NodeRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisNetwork.NodeSupervisor},
      UnirisNetwork.GeoPatch,
      UnirisNetwork.ChainLoader,
      :ranch.child_spec(
        :p2p_server,
        :ranch_tcp,
        [{:port, port}],
        UnirisNetwork.P2P.ConnectionHandler,
        []
      )
    ]

    Logger.info("Listening on port: #{port}")

    Supervisor.start_link(children, strategy: :one_for_one, name: UnirisNetwork.Supervisor)
  end
end
