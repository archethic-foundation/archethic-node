defmodule Archethic.P2P.Client.ConnectionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Archethic.P2P.Client.Connection

  def start_link(arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_connection(opts \\ []) do
    node_public_key = Keyword.get(opts, :node_public_key)
    opts = Keyword.put(opts, :from, self())

    DynamicSupervisor.start_child(
      __MODULE__,
      %{
        id: {Connection, node_public_key},
        start: {Connection, :start_link, [opts]},
        type: :worker
      }
    )
  end

  @doc """
  Terminate a connection process
  """
  @spec cancel_connection(pid) :: :ok | {:error, :not_found}
  def cancel_connection(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
