defmodule Uniris.P2P do
  @moduledoc """
  Handle P2P node discovery and messaging
  """
  alias Uniris.Crypto

  alias __MODULE__.BootstrappingSeeds
  alias __MODULE__.Client
  alias __MODULE__.Client.TransportImpl
  alias __MODULE__.ClientConnection
  alias __MODULE__.ConnectionSupervisor
  alias __MODULE__.GeoPatch
  alias __MODULE__.MemTable
  alias __MODULE__.MemTableLoader
  alias __MODULE__.Message
  alias __MODULE__.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.Utils

  require Logger

  @doc """
  Compute a geographical patch (zone) from an IP
  """
  @spec get_geo_patch(:inet.ip_address()) :: binary()
  defdelegate get_geo_patch(ip), to: GeoPatch, as: :from_ip

  @doc """
  Register a node
  """
  @spec add_node(Node.t()) :: :ok
  def add_node(node = %Node{}) do
    :ok = MemTable.add_node(node)
    do_connect_node(node)
  end

  defp do_connect_node(%Node{first_public_key: key, ip: ip, port: port, transport: transport}) do
    if key == Crypto.node_public_key(0) do
      :ok
    else
      # Avoid to open connection during testing
      transport_impl =
        :uniris
        |> Application.get_env(Client, impl: TransportImpl)
        |> Keyword.fetch!(:impl)

      case transport_impl do
        TransportImpl ->
          DynamicSupervisor.start_child(
            ConnectionSupervisor,
            {ClientConnection, ip: ip, port: port, transport: transport, node_public_key: key}
          )

          :ok

        _ ->
          :ok
      end
    end
  end

  @doc """
  List the nodes registered.

  Options are used to filter the selection:
  - `availability`: filter nodes based on the level of availability:
    - `global`: Node discovered and available from the beacon chain daily summary
    - `local`: Node discovered and available from the last exchange
  - `authorized?`: if `true`, take only the authorized nodes
  """
  @spec list_nodes(opts :: [availability: :global | :local, authorized?: boolean()]) ::
          list(Node.t())
  defdelegate list_nodes(opts \\ []), to: MemTable

  @doc """
  Reset the authorized nodes list
  """
  @spec reset_authorized_nodes() :: :ok
  defdelegate reset_authorized_nodes, to: MemTable

  @doc """
  Add a node first public key to the list of nodes globally available.
  """
  @spec set_node_globally_available(first_public_key :: Crypto.key()) :: :ok
  defdelegate set_node_globally_available(first_public_key), to: MemTable, as: :set_node_available

  @doc """
  Add a node first public key to the list of authorized nodes
  """
  @spec authorize_node(first_public_key :: Crypto.key(), authorization_date :: DateTime.t()) ::
          :ok
  defdelegate authorize_node(first_public_key, authorization_date), to: MemTable

  @doc """
  List the first node public keys
  """
  @spec list_node_first_public_keys() :: list(Crypto.key())
  defdelegate list_node_first_public_keys, to: MemTable

  @doc """
  List the authorized node public keys
  """
  @spec list_authorized_public_keys() :: list(Crypto.key())
  defdelegate list_authorized_public_keys, to: MemTable

  @doc """
  Returns node information from a given node first public key
  """
  @spec get_node_info(Crypto.key()) :: {:ok, Node.t()} | {:error, :not_found}
  defdelegate get_node_info(key), to: MemTable, as: :get_node

  @doc """
  Returns node information from a given node first public key.

  Raise an error if the node key does not exists
  """
  @spec get_node_info!(Crypto.key()) :: Node.t()
  def get_node_info!(key) do
    case get_node_info(key) do
      {:ok, node} ->
        node

      {:error, :not_found} ->
        raise "Node Not Found"
    end
  end

  @doc """
  Returns information about the running node
  """
  @spec get_node_info() :: Node.t()
  def get_node_info do
    {:ok, node} = get_node_info(Crypto.node_public_key(0))
    node
  end

  @doc """
  Send a P2P message to a node.

  If the exchange fails, the node availability history will decrease
  and will be locally unavailable until the next exchange
  """
  @spec send_message(Crypto.key() | Node.t(), Message.t()) :: Message.t()
  def send_message(public_key, message) when is_binary(public_key) do
    {:ok, node} = get_node_info(public_key)
    send_message(node, message)
  end

  def send_message(node = %Node{}, message), do: Client.send_message(node, message)

  @doc """
  Get the nearest nodes from a specified node and a list of nodes to compare with

  ## Examples

     iex> list_nodes = [%Node{network_patch: "AA0"}, %Node{network_patch: "F50"}, %Node{network_patch: "3A2"}]
     iex> P2P.nearest_nodes(list_nodes, "12F")
     [
       %Node{network_patch: "3A2"},
       %Node{network_patch: "AA0"},
       %Node{network_patch: "F50"}
     ]

     iex> list_nodes = [%Node{network_patch: "AA0"}, %Node{network_patch: "F50"}, %Node{network_patch: "3A2"}]
     iex> P2P.nearest_nodes(list_nodes, "C3A")
     [
       %Node{network_patch: "AA0"},
       %Node{network_patch: "F50"},
       %Node{network_patch: "3A2"}
     ]
  """
  @spec nearest_nodes(node_list :: Enumerable.t(), network_patch :: binary()) :: Enumerable.t()
  def nearest_nodes(storage_nodes, network_patch) when is_binary(network_patch) do
    Enum.sort_by(storage_nodes, &GeoPatch.diff(&1.network_patch, network_patch))
  end

  @doc """
  Return the nearest storages nodes from the local node
  """
  @spec nearest_nodes(list(Node.t())) :: list(Node.t())
  def nearest_nodes(storage_nodes) when is_list(storage_nodes) do
    %Node{network_patch: network_patch} = get_node_info()
    nearest_nodes(storage_nodes, network_patch)
  end

  @doc """
  Return a list of nodes information from a list of public keys
  """
  @spec get_nodes_info(list(Crypto.key())) :: list(Node.t())
  def get_nodes_info(public_keys) when is_list(public_keys) do
    Enum.map(public_keys, fn key ->
      {:ok, node} = get_node_info(key)
      node
    end)
  end

  @doc """
  Distinct nodes list by the first public keys.

  If the list contains sublist, the list will be flatten

  ## Examples

      iex> [
      ...>   %Node{first_public_key: "key1"},
      ...>   %Node{first_public_key: "key2"},
      ...>   [%Node{first_public_key: "key3"}, %Node{first_public_key: "key1"}]
      ...> ]
      ...> |> P2P.distinct_nodes()
      [
        %Node{first_public_key: "key1"},
        %Node{first_public_key: "key2"},
        %Node{first_public_key: "key3"}
      ]
  """
  @spec distinct_nodes(list(Node.t() | list(Node.t()))) :: list(Node.t())
  def distinct_nodes(nodes) when is_list(nodes) do
    nodes
    |> :lists.flatten()
    |> Enum.uniq_by(& &1.first_public_key)
  end

  @doc """
  Get the first node public key from a last one
  """
  @spec get_first_node_key(Crypto.key()) :: Crypto.key()
  defdelegate get_first_node_key(key), to: MemTable

  @doc """
  Send a message to a list of nodes and return a stream of response

  Available options:
  - ack_node?: can require node acknowledgement to return the node which respond
  - timeout: timeout before the concurrent request is cancelled
  """
  @spec broadcast_message(list(Node.t()), Message.t(), opts :: Keyword.t()) :: Enumerable.t()
  def broadcast_message(nodes, message, opts \\ [ack_node?: false, timeout: 5_000]) do
    ack_node? = Keyword.get(opts, :ack_node?, false)
    timeout = Keyword.get(opts, :timeout, 5_000)

    nodes
    |> Task.async_stream(
      fn node ->
        {send_message(node, message), node}
      end,
      ordered: false,
      on_timeout: :kill_task,
      timeout: timeout
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, {res, node}} ->
      if ack_node? do
        {res, node}
      else
        res
      end
    end)
  end

  @doc """
  List the current bootstrapping network seeds
  """
  @spec list_bootstrapping_seeds() :: list(Node.t())
  defdelegate list_bootstrapping_seeds, to: BootstrappingSeeds, as: :list

  @doc """
  Update the bootstrapping network seeds and flush them
  """
  @spec new_bootstrapping_seeds(list(Node.t())) :: :ok
  defdelegate new_bootstrapping_seeds(nodes), to: BootstrappingSeeds, as: :update

  @doc """
  Create a binary sequence from a list node and set bit regarding their availability

  ## Examples

      iex> P2P.nodes_availability_as_bits([
      ...>   %Node{availability_history: <<1::1, 0::1>>},
      ...>   %Node{availability_history: <<0::1, 1::1>>},
      ...>   %Node{availability_history: <<1::1, 0::1>>}
      ...> ])
      <<1::1, 0::1, 1::1>>
  """
  @spec nodes_availability_as_bits(list(Node.t())) :: bitstring()
  def nodes_availability_as_bits(node_list) when is_list(node_list) do
    Enum.reduce(node_list, <<>>, fn node, acc ->
      if Node.locally_available?(node) do
        <<acc::bitstring, 1::1>>
      else
        <<acc::bitstring, 0::1>>
      end
    end)
  end

  @doc """
  Create a sequence of bits from a list of node and a subset
  by setting the bit where the subset node if found

  ## Examples

      iex> node_list = [
      ...>  %Node{first_public_key: "key1"},
      ...>  %Node{first_public_key: "key2"},
      ...>  %Node{first_public_key: "key3"}
      ...> ]
      iex> subset = [%Node{first_public_key: "key2"}]
      iex> P2P.bitstring_from_node_subsets(node_list, subset)
      <<0::1, 1::1, 0::1>>

      iex> node_list = [
      ...>  %Node{first_public_key: "key1"},
      ...>  %Node{first_public_key: "key2"},
      ...>  %Node{first_public_key: "key3"}
      ...> ]
      iex> subset = [%Node{first_public_key: "key2"}, %Node{first_public_key: "key3"}]
      iex> P2P.bitstring_from_node_subsets(node_list, subset)
      <<0::1, 1::1, 1::1>>
  """
  @spec bitstring_from_node_subsets(
          node_list :: list(Node.t()),
          subset :: list(Node.t())
        ) ::
          bitstring()
  def bitstring_from_node_subsets(node_list, subset)
      when is_list(node_list) and is_list(subset) do
    nb_nodes = length(node_list)
    from_node_subset(node_list, subset, 0, <<0::size(nb_nodes)>>)
  end

  defp from_node_subset([%Node{first_public_key: first_public_key} | rest], subset, index, acc) do
    if Enum.any?(subset, &(&1.first_public_key == first_public_key)) do
      from_node_subset(rest, subset, index + 1, Utils.set_bitstring_bit(acc, index))
    else
      from_node_subset(rest, subset, index + 1, acc)
    end
  end

  defp from_node_subset([], _subset, _index, acc), do: acc

  @doc """
  Load the transaction into the P2P context updating the P2P view
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(tx), to: MemTableLoader
end
