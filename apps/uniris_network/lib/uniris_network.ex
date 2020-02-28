defmodule UnirisNetwork do
  @moduledoc """
  Uniris's network supports a supervised P2P communication helpful to determine a local P2P view of the network and node shared secrets
  which handle authorization and access - preventing malicious nodes to validate transaction.

  During the node bootstraping, the node shared secrets and node listing are loading from the transaction chain to enable a fast read and processing.

  This module provides interface to get the node shared secrets, the network nodes information and communicate with them throught P2P requests.

  """

  alias UnirisNetwork.Node
  alias UnirisCrypto, as: Crypto

  @behaviour UnirisNetwork.Impl

  @doc """
  Get the storage nonce used in the storage node election

  This nonce should not change to preserve the discoverabiliy of nodes tIt will be loaded during the node bootstraping.

  """
  @impl true
  @spec storage_nonce() :: binary()
  def storage_nonce() do
    impl().storage_nonce()
  end

  @doc """
  Get the daily nonce used in the validation node election.

  This nonce will change everyday through the process of renewal of node shared secrets.

  """
  @impl true
  @spec daily_nonce() :: binary()
  def daily_nonce() do
    impl().daily_nonce()
  end

  @doc """
  Change the daily nonce with the given value.
  """
  @impl true
  @spec set_daily_nonce(binary()) :: :ok
  def set_daily_nonce(nonce) do
    impl().set_daily_nonce(nonce)
  end

  @doc """
  Retrieve the origin public keys used to determine the proof of work.
  """
  @impl true
  @spec origin_public_keys() :: list(binary())
  def origin_public_keys() do
    impl().origin_public_keys()
  end

  @doc """
  Get the list of node in the networik

  This list is loaded on the node bootstraping from the TransactionChains of everynode and is changed when nodes are added or evicted
  through the node shared secret renewal.
  """
  @impl true
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    impl().list_nodes()
  end

  @doc """
  Add a node in the Uniris network
  """
  @impl true
  @spec add_node(Node.t()) :: :ok
  def add_node(node = %Node{}) do
    impl().add_node(node)
  end

  @doc """
  Retreive node information from a public key
  """
  @impl true
  @spec node_info(binary()) :: Node.t()
  def node_info(public_key) when is_binary(public_key) do
    impl().node_info(public_key)
  end

  @doc """
  Retrieve node information from an IP.
  """
  @impl true
  @spec node_info(:inet.ip_address()) :: Node.t()
  def node_info(ip = {_, _, _, _}) do
    impl().node_info(ip)
  end

  @doc """
  Send a P2P message to a remote node
  """
  @impl true
  @spec send_message(Node.t(), term()) :: {:ok, data :: term()} | {:error, reason :: atom()}
  def send_message(node = %Node{}, message) do
    impl().send_message(node, message)
  end

  @doc """
  Get the nearest nodes from a specified node and a list of nodes to compare with

  ## Examples

     iex> list_nodes = [%{network_patch: "AA0"}, %{network_patch: "F50"}, %{network_patch: "3A2"}]
     iex> from_node = %{network_patch: "12F"}
     iex> UnirisNetwork.nearest_nodes(from_nodes, list_nodes)
     [
       %{network_patch: "3A2"},
       %{network_patch: "AA0"},
       %{network_patch: "F50"}
     ]
  """
  @spec nearest_nodes(Node.t(), nonempty_list(Node.t())) :: list(Node.t())
  def nearest_nodes(from_node = %Node{}, storage_nodes) when is_list(storage_nodes) do
    from_node_position = from_node.network_patch |> String.to_charlist() |> List.to_integer(16)

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
  def nearest_nodes(storage_nodes) when is_list(storage_nodes) do
    pub = Crypto.last_node_public_key()
    me = node_info(pub)
    nearest_nodes(me, storage_nodes)
  end

  defp impl(), do: Application.get_env(:uniris_network, :impl, __MODULE__.DefaultImpl)
end
