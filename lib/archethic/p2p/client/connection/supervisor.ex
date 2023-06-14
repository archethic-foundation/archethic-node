defmodule Archethic.P2P.Client.ConnectionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Archethic.Crypto

  alias Archethic.P2P.Client.Connection

  @table_name :connection_status

  def start_link(arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    # Start an ets table to manage node connection status.
    # This reduce the number of message sent to the Connection GenServer
    if :ets.whereis(@table_name) == :undefined do
      # Create ets table only if it doesn't exist (init of supervisor called in hot reload)
      :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    end

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_connection(opts \\ []) do
    node_public_key = Keyword.get(opts, :node_public_key)
    opts = Keyword.put(opts, :from, self())

    :ets.insert(@table_name, {node_public_key, false})

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
  @spec cancel_connection(pid :: pid(), node_public_key :: Crypto.key()) ::
          :ok | {:error, :not_found}
  def cancel_connection(pid, node_public_key) do
    :ets.delete(@table_name, node_public_key)

    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Return true if the connection is established
  """
  @spec node_connected?(node_public_key :: Crypto.key()) :: boolean()
  def node_connected?(node_public_key) do
    :ets.lookup_element(@table_name, node_public_key, 2)
  end

  @doc """
  Set node connection status to connected
  """
  @spec set_node_connected(node_public_key :: Crypto.key()) :: boolean()
  def set_node_connected(node_public_key),
    do: :ets.update_element(@table_name, node_public_key, {2, true})

  @doc """
  Set node connection status to disconnected
  """
  @spec set_node_disconnected(node_public_key :: Crypto.key()) :: boolean()
  def set_node_disconnected(node_public_key),
    do: :ets.update_element(@table_name, node_public_key, {2, false})
end
