defmodule Archethic.OracleChain.ServiceCacheSupervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.OracleChain.Services

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = Services.cache_service_supervisor_specs()
    Supervisor.init(children, strategy: :one_for_one)
  end
end
