defmodule Archethic.Replication.Supervisor do
  @moduledoc false

  alias Archethic.Replication.TransactionPool

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    children = [
      TransactionPool
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
