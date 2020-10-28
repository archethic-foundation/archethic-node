defmodule Uniris.P2P.Endpoint.ListenerSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.P2P.Endpoint.AcceptorSupervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    children = [
      {Task.Supervisor, strategy: :one_for_one, name: Uniris.P2P.Endpoint.ConnectionSupervisor},
      {AcceptorSupervisor, args}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
