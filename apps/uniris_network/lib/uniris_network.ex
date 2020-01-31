defmodule UnirisNetwork do
  @moduledoc """
  Uniris's network supports a supervised P2P communication helpful to determine a local P2P view of the network and node shared secrets
  which handle authorization and access - preventing malicious nodes to validate transaction.

  During the node bootstraping, the node shared secrets and node listing are loading in memory into specific processes
  from the transaction chain to enable a fast read and processing.

  This module provides interface to get the node shared secrets, the network nodes and communicate with them throught P2P requests.

  """

  alias UnirisNetwork.Node

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
  Retreive node information from a public key 
  """
  @impl true
  @spec node_info(binary()) :: {:ok, Node.t()} | {:error, :node_not_exists}
  def node_info(public_key) do
    impl().node_info(public_key)
  end

  defp impl(), do: Application.get_env(:uniris_network, :impl, __MODULE__.DefaultImpl)
end
