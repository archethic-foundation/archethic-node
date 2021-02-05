defmodule Uniris.P2P.ConnectionPool do
  @moduledoc """
  Handle the node connection pools
  """

  alias Uniris.Crypto

  alias __MODULE__.Worker

  alias Uniris.P2P.ConnectionPoolsRegistry
  alias Uniris.P2P.ConnectionPoolsSupervisor

  alias Uniris.P2P.Node

  @doc """
  Add a new connection pool child to the pools supervisor for the given node.

  It will spawn few workers to handle the node connections
  """
  @spec add_node_connection_pool(Node.t()) :: {:ok, pid()}
  def add_node_connection_pool(%Node{
        ip: ip,
        port: port,
        transport: transport,
        first_public_key: node_public_key
      }) do
    child_spec =
      :poolboy.child_spec(:worker, poolboy_config(node_public_key),
        ip: ip,
        port: port,
        transport: transport
      )

    case DynamicSupervisor.start_child(ConnectionPoolsSupervisor, child_spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}
    end
  end

  @doc """
  Send a message to a node through one of its workers
  """
  @spec send_message(Crypto.key(), binary()) ::
          {:ok, binary()} | {:error, :disconnected} | {:error, :network_issue}
  def send_message(node_public_key, message)
      when is_binary(node_public_key) and is_binary(message) do
    :poolboy.transaction(
      {:via, Registry, {ConnectionPoolsRegistry, node_public_key}},
      fn pid -> Worker.send_message(pid, message) end,
      10_000
    )
  end

  @doc """
  Return all the workers for the give node connection pool
  """
  @spec workers(Crypto.key()) :: list(pid())
  def workers(node_public_key) when is_binary(node_public_key) do
    GenServer.call(
      {:via, Registry, {ConnectionPoolsRegistry, node_public_key}},
      :get_avail_workers
    )
  end

  defp poolboy_config(node_public_key) do
    [
      name: {:via, Registry, {ConnectionPoolsRegistry, node_public_key}},
      worker_module: Worker,
      size: 10,
      max_overflow: 2
    ]
  end
end
