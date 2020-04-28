defmodule UnirisCore.P2P do
  alias __MODULE__.GeoPatch
  alias __MODULE__.Node
  alias UnirisCore.Crypto
  alias UnirisCore.P2P.NodeRegistry
  alias UnirisCore.P2P.NodeSupervisor

  require Logger

  @doc """
  Perform a lookups to find a patch from an ip
  """
  @spec get_geo_patch(:inet.ip_address()) :: binary()
  def get_geo_patch({_, _, _, _} = ip) do
    GeoPatch.from_ip(ip)
  end

  @doc """
  Return the list of nodes
  """
  @spec list_nodes() ::
          list(Node.t())
  def list_nodes() do
    DynamicSupervisor.which_children(NodeSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> Node.details(pid) end)
  end

  @doc """
  Add a new node process under supervision
  """
  @spec add_node(Node.t()) :: :ok
  def add_node(node = %Node{}) do
    {:ok, _} =
      DynamicSupervisor.start_child(
        NodeSupervisor,
        {Node, node}
      )

    Logger.debug("New node added #{Base.encode16(node.first_public_key)}")
  end

  @doc """
  Get the node details from its public key or ip address
  """
  @spec node_info(UnirisCore.Crypto.key()) :: {:ok, Node.t()} | {:error, :not_found}
  def node_info(public_key) when is_binary(public_key) do
    case Registry.lookup(NodeRegistry, public_key) do
      [] ->
        {:error, :not_found}

      _ ->
        details = Node.details(public_key)
        {:ok, details}
    end
  end

  @spec node_info(:inet.ip_address()) :: {:ok, Node.t()} | {:error, :not_found}
  def node_info(ip = {_, _, _, _}) do
    case Registry.lookup(NodeRegistry, ip) do
      [] ->
        {:error, :not_found}

      _ ->
        details = Node.details(ip)
        {:ok, details}
    end
  end

  @doc """
  Returns information about the running node
  """
  @spec node_info() :: Node.t() | nil
  def node_info() do
    case node_info(Crypto.node_public_key(0)) do
      {:ok, node} ->
        node

      _ ->
        nil
    end
  end

  @doc """
  Send a P2P message to a node. The public keys helps to identify which supervised connection to use
  """
  @spec send_message(UnirisCore.Crypto.key(), term()) :: any()
  def send_message(public_key, message) when is_binary(public_key) do
    Node.send_message(public_key, message)
  end

  @spec send_message(Node.t(), term()) :: any()
  def send_message(%Node{first_public_key: first_public_key}, message) do
    Node.send_message(first_public_key, message)
  end

  @spec send_message(:inet.ip_address(), term()) :: any()
  def send_message({_, _, _, _} = ip, message) do
    {:ok, %Node{first_public_key: public_key}} = node_info(ip)
    Node.send_message(public_key, message)
  end

  @doc """
  Get the nearest nodes from a specified node and a list of nodes to compare with

  ## Examples

     iex> list_nodes = [%{network_patch: "AA0"}, %{network_patch: "F50"}, %{network_patch: "3A2"}]
     iex> UnirisCore.P2P.nearest_nodes(list_nodes, "12F")
     [
       %{network_patch: "3A2"},
       %{network_patch: "AA0"},
       %{network_patch: "F50"}
     ]

     iex> list_nodes = [%{network_patch: "AA0"}, %{network_patch: "F50"}, %{network_patch: "3A2"}]
     iex> UnirisCore.P2P.nearest_nodes(list_nodes, "C3A")
     [
       %{network_patch: "AA0"},
       %{network_patch: "F50"},
       %{network_patch: "3A2"}
     ]
  """
  @spec nearest_nodes(network_patch :: binary(), node_list :: nonempty_list(Node.t())) ::
          list(Node.t())
  def nearest_nodes(storage_nodes, network_patch)
      when is_list(storage_nodes) and is_binary(network_patch) do
    from_node_position = network_patch |> String.to_charlist() |> List.to_integer(16)

    Enum.sort_by(storage_nodes, fn storage_node ->
      storage_node_position =
        storage_node.network_patch |> String.to_charlist() |> List.to_integer(16)

      abs(storage_node_position - from_node_position)
    end)
  end
end
