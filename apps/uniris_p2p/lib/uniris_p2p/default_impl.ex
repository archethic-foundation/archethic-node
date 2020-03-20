defmodule UnirisP2P.DefaultImpl do
  @moduledoc false

  @behaviour UnirisP2P.Impl

  alias __MODULE__.SupervisedConnection
  alias __MODULE__.SeedLoader
  alias UnirisP2P.ConnectionSupervisor
  alias UnirisP2P.NodeSupervisor
  alias UnirisP2P.Node
  alias UnirisP2P.NodeRegistry

  @impl true
  @spec connect_node(Node.t()) :: :ok
  def connect_node(%Node{ip: ip, port: port, first_public_key: public_key}) do
    DynamicSupervisor.start_child(
      ConnectionSupervisor,
      {SupervisedConnection, ip: ip, port: port, public_key: public_key}
    )

    :ok
  end

  @impl true
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    DynamicSupervisor.which_children(NodeSupervisor)
    |> Task.async_stream(fn {:undefined, pid, _, _} -> Node.details(pid) end)
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  @impl true
  @spec authorized_nodes() :: list(Node.t())
  def authorized_nodes() do
    Enum.filter(list_nodes(), &(&1.authorized?))
  end

  @impl true
  @spec add_node(Node.t()) :: :ok
  def add_node(%Node{
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        ip: ip,
        port: port
      }) do
    case Registry.lookup(NodeRegistry, first_public_key) do
      [{_, _}] ->
        Node.update_basics(first_public_key, last_public_key, ip, port)

      _ ->
        {:ok, _} =
          DynamicSupervisor.start_child(
            NodeSupervisor,
            {Node,
             first_public_key: first_public_key,
             last_public_key: last_public_key,
             ip: ip,
             port: port}
          )
    end

    :ok
  end

  @impl true
  @spec node_info(UnirisCrypto.key()) :: {:ok, Node.t()} | {:error, :not_found}
  def node_info(public_key) when is_binary(public_key) do
    try do
      {:ok, Node.details(public_key)}
    rescue
      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  @spec node_info(:inet.ip_address()) :: {:ok, Node.t()} | {:error, :not_found}
  def node_info(ip = {_, _, _, _}) do
    try do
      {:ok, Node.details(ip)}
    rescue
      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  @spec send_message(UnirisCrypto.key(), term()) :: any()
  def send_message(public_key, message) when is_binary(public_key) do
    SupervisedConnection.send_message(public_key, message)
  end

  @impl true
  @spec send_message(Node.t(), term()) :: any()
  def send_message(%Node{first_public_key: first_public_key}, message) do
    SupervisedConnection.send_message(first_public_key, message)
  end

  @impl true
  @spec send_message(:inet.ip_address(), term()) :: any()
  def send_message({_, _, _, _} = ip, message) do
    {:ok, %Node{first_public_key: public_key}} = node_info(ip)
    SupervisedConnection.send_message(public_key, message)
  end

  @impl true
  @spec list_seeds() :: list(Node.t())
  def list_seeds() do
    SeedLoader.list()
  end

  @impl true
  @spec update_seeds(list(Node.t())) :: :ok
  def update_seeds(seeds) do
    SeedLoader.update(seeds)
  end
end
