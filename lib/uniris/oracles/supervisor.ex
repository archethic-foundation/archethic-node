defmodule Uniris.Oracles.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Oracles.{
    Coingecko, 
    OracleCronServer
  }
  alias Uniris.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    optional_children = [
      {OracleCronServer, [mfa: {Coingecko, :fetch, [DateTime.utc_now]}, interval: 5_000], id: :a},
      {OracleCronServer, [mfa: {Coingecko, :fetch, [DateTime.new!(~D[2020-12-31], ~T[00:00:00.000], "Etc/UTC")]}, interval: 10_000], id: :b}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def state do
    res = Supervisor.which_children(__MODULE__)
    |> Enum.map(fn({_id, pid, :worker, _modules}) -> OracleCronServer.get_payload(pid) end)
    
    IO.puts "RES: #{inspect res}"
  end
end
