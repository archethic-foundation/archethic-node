defmodule UnirisP2P do
  alias __MODULE__.Node
  alias UnirisCrypto, as: Crypto

  @behaviour __MODULE__.Impl

  @impl true
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    impl().list_nodes()
  end

  @impl true
  @spec add_node(Node.t()) :: :ok
  def add_node(node = %Node{}) do
    impl().add_node(node)
  end

  @impl true
  @spec node_info(UnirisCrypto.key()) :: {:ok, Node.t()} | {:error, :not_found}
  def node_info(key) when is_binary(key) do
    impl().node_info(key)
  end

  @impl true
  @spec node_info(:inet.ip_address()) :: {:ok, Node.t()} | {:error, :not_found}
  def node_info(ip = {_, _, _, _}) do
    impl().node_info(ip)
  end

  @doc """
  Establishes a new long-living P2P connection with monitoring to detect any disturbance to provide an real time P2P view of
  the availables nodes
  """
  @impl true
  @spec connect_node(Node.t()) :: :ok
  def connect_node(node = %Node{}) do
    impl().connect_node(node)
  end

  @doc """
  Send a P2P message to a node. The public keys helps to identify which supervised connection to use
  """
  @impl true
  @spec send_message(UnirisCrypto.key(), term()) :: any()
  def send_message(public_key, message) when is_binary(public_key) do
    impl().send_message(public_key, message)
  end

  @impl true
  @spec send_message(Node.t(), term()) :: any()
  def send_message(node = %Node{}, message) do
    impl().send_message(node, message)
  end

  @impl true
  @spec send_message(:inet.ip_address(), term()) :: any()
  def send_message({_, _, _, _} = ip, message) do
    impl().send_message(ip, message)
  end

  @doc """
  List the P2P bootstraping seeds
  """
  @impl true
  @spec list_seeds() :: list(Node.t())
  def list_seeds() do
    impl().list_seeds()
  end

  @doc """
  Update the P2P bootstraping seeds
  """
  @impl true
  @spec update_seeds(list(Node.t())) :: :ok
  def update_seeds(seeds) do
    impl().update_seeds(seeds)
  end

  @doc """
  Get the nearest nodes from a specified node and a list of nodes to compare with

  ## Examples

     iex> list_nodes = [%{network_patch: "AA0"}, %{network_patch: "F50"}, %{network_patch: "3A2"}]
     iex> UnirisP2P.nearest_nodes("12F", list_nodes)
     [
       %{network_patch: "3A2"},
       %{network_patch: "AA0"},
       %{network_patch: "F50"}
     ]
  """
  @spec nearest_nodes(network_patch :: binary(), node_list :: nonempty_list(Node.t())) ::
          list(Node.t())
  def nearest_nodes(network_patch, storage_nodes) when is_list(storage_nodes) do
    from_node_position = network_patch |> String.to_charlist() |> List.to_integer(16)

    Enum.sort_by(storage_nodes, fn storage_node ->
      storage_node_position =
        storage_node.network_patch |> String.to_charlist() |> List.to_integer(16)

      abs(storage_node_position - from_node_position)
    end)
  end

  @doc """
  Get the nearest from me and the a list of nodes to compare with
  """
  @spec nearest_nodes(list(Node.t())) :: list(Node.t())
  def nearest_nodes(storage_nodes) do
    {:ok, %Node{network_patch: patch}} = node_info(Crypto.node_public_key())
    nearest_nodes(patch, storage_nodes)
  end

  defp impl() do
    Application.get_env(:uniris_p2p, :impl, __MODULE__.DefaultImpl)
  end
end
