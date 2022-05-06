defmodule Archethic.P2P.Client.ConnectionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Archethic.P2P.Client.Connection

  def start_link(arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:connection_requests, [:set, :named_table, :public])
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_connection(opts \\ []) do
    node_public_key = Keyword.get(opts, :node_public_key)

    DynamicSupervisor.start_child(
      __MODULE__,
      %{
        id: {Connection, node_public_key},
        start: {Connection, :start_link, [opts]},
        type: :worker
      }
    )
  end
end
