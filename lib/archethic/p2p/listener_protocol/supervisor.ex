defmodule Archethic.P2P.ListenerProtocol.Supervisor do
  @moduledoc false

  alias Archethic.P2P.ListenerProtocol.BroadwayPipelineRegistry
  alias Archethic.P2P.ListenerProtocol.MessageProducerRegistry

  use Supervisor

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    children = [
      {Registry, name: BroadwayPipelineRegistry, keys: :unique},
      {Registry, name: MessageProducerRegistry, keys: :unique}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
