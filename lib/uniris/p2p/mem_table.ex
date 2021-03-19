defmodule Uniris.P2P.MemTable do
  @moduledoc false

  @discovery_table :uniris_node_discovery
  @nodes_key_lookup_table :uniris_node_keys
  @availability_lookup_table :uniris_available_nodes
  @authorized_nodes_table :uniris_authorized_nodes

  alias Uniris.Crypto

  alias Uniris.P2P.Node

  alias Uniris.PubSub

  use GenServer

  require Logger

  @doc """
  Initialize the memory tables for the P2P view

  ## Examples

      iex> {:ok, _} = MemTable.start_link()
      iex> {
      ...>    :ets.info(:uniris_node_discovery)[:type],
      ...>    :ets.info(:uniris_node_keys)[:type],
      ...>    :ets.info(:uniris_available_nodes)[:type],
      ...>    :ets.info(:uniris_authorized_nodes)[:type],
      ...>  }
      { :set, :set, :set, :set }
  """
  @spec start_link([]) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@discovery_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@availability_lookup_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@authorized_nodes_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@nodes_key_lookup_table, [:set, :named_table, :public, read_concurrency: true])

    Logger.info("Initialize InMemory P2P view")

    {:ok, []}
  end

  @doc """
  Add a node into the P2P view.

  If a node already exists with the first public key, the P2P information will be updated.

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   geo_patch: "AFZ",
      ...>   network_patch: "AAA",
      ...>   availability_history: <<1::1, 1::1>>,
      ...>   average_availability: 0.9,
      ...>   available?: true,
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   enrollment_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   transport: :tcp
      ...> }
      iex> :ok = MemTable.add_node(node)
      iex> {
      ...>   :ets.tab2list(:uniris_node_discovery),
      ...>   :ets.tab2list(:uniris_available_nodes),
      ...>   :ets.tab2list(:uniris_authorized_nodes),
      ...>   :ets.tab2list(:uniris_node_keys)
      ...>  }
      {
        # Discovery table
        [{
          "key1", "key2", {127, 0, 0, 1}, 3000, "AFZ", "AAA", 0.9, <<1::1, 1::1>>, ~U[2020-10-22 23:19:45.797109Z], :tcp
        }],
        # Globally available nodes
        [{ "key1" }],
        # Authorized nodes
        [{ "key1",  ~U[2020-10-22 23:19:45.797109Z] }],
        # Node key lookup
        [{"key2", "key1"}]
      }

    Update the node P2P view if exists

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   geo_patch: "AFZ",
      ...>   network_patch: "AAA",
      ...>   availability_history: <<1::1, 1::1>>,
      ...>   average_availability: 0.9,
      ...>   available?: true,
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   enrollment_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   transport: :tcp
      ...> }
      iex> :ok = MemTable.add_node(node)
      iex> :ok = MemTable.add_node(%Node{
      ...>   ip: {80, 20, 10, 122},
      ...>   port: 5000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key5",
      ...>   average_availability: 0.9,
      ...>   availability_history: <<1::1, 1::1>>,
      ...>   transport: :sctp
      ...>  })
      iex> :ets.lookup(:uniris_node_discovery, "key1")
      [{"key1", "key5", {80, 20, 10, 122}, 5000, "AFZ", "AAA", 0.9, <<1::1, 1::1>>, ~U[2020-10-22 23:19:45.797109Z], :sctp}]
  """
  @spec add_node(Node.t()) :: :ok
  def add_node(
        node = %Node{
          first_public_key: first_public_key,
          last_public_key: last_public_key,
          available?: available?,
          authorized?: authorized?,
          authorization_date: authorization_date
        }
      ) do
    if node_exists?(first_public_key) do
      update_p2p_discovery(node)
      Logger.info("Node update", node: Base.encode16(first_public_key))
      Logger.debug("Update info: #{inspect(node)}", node: Base.encode16(first_public_key))
    else
      insert_p2p_discovery(node)

      Logger.info("Node joining", node: Base.encode16(first_public_key))
      Logger.debug("Node info: #{inspect(node)}", node: Base.encode16(first_public_key))
    end

    index_node_public_keys(first_public_key, last_public_key)

    if authorized? do
      authorize_node(first_public_key, authorization_date)
    end

    if available? do
      set_node_available(first_public_key)
    end

    notify_node_update(first_public_key)

    :ok
  end

  defp node_exists?(public_key) do
    :ets.member(@discovery_table, public_key)
  end

  defp insert_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         ip: ip,
         port: port,
         geo_patch: geo_patch,
         network_patch: network_patch,
         enrollment_date: enrollment_date,
         average_availability: average_availability,
         availability_history: availability_history,
         transport: transport
       }) do
    :ets.insert(
      @discovery_table,
      {first_public_key, last_public_key, ip, port, geo_patch, network_patch,
       average_availability, availability_history, enrollment_date, transport}
    )
  end

  defp update_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         ip: ip,
         port: port,
         geo_patch: geo_patch,
         network_patch: network_patch,
         average_availability: average_availability,
         availability_history: availability_history,
         enrollment_date: enrollment_date,
         transport: transport
       }) do
    :ets.update_element(@discovery_table, first_public_key, [
      {2, last_public_key},
      {3, ip},
      {4, port},
      {10, transport}
    ])

    if geo_patch != nil do
      :ets.update_element(@discovery_table, first_public_key, [{5, geo_patch}])
    end

    if network_patch != nil do
      :ets.update_element(@discovery_table, first_public_key, [{6, network_patch}])
    end

    if average_availability != nil do
      :ets.update_element(@discovery_table, first_public_key, [{7, average_availability}])
    end

    if availability_history != nil do
      :ets.update_element(@discovery_table, first_public_key, [{8, availability_history}])
    end

    if enrollment_date != nil do
      :ets.update_element(@discovery_table, first_public_key, [{9, enrollment_date}])
    end
  end

  defp index_node_public_keys(first_public_key, last_public_key) do
    true = :ets.insert(@nodes_key_lookup_table, {last_public_key, first_public_key})
  end

  @doc """
  Retrieve the node entry by its first public key by default otherwise perform
  a lookup to retrieved it by the last key.

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> :ok = MemTable.add_node(node)
      iex> {:ok, node} == MemTable.get_node("key1")
      true

    Retrieve by the last public key will perform a lookup to get the first one

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> :ok = MemTable.add_node(node)
      iex> {:ok, node} == MemTable.get_node("key2")
      true

    Returns an error if the node is not present

      iex> MemTable.start_link()
      iex> MemTable.get_node("key10")
      {:error, :not_found}
  """
  @spec get_node(public_key :: Crypto.key()) :: {:ok, Node.t()} | {:error, :not_found}
  def get_node(key) do
    case :ets.lookup(@discovery_table, get_first_node_key(key)) do
      [] ->
        {:error, :not_found}

      [res] ->
        node =
          res
          |> Node.cast()
          |> toggle_node_authorization
          |> toggle_node_availability

        {:ok, node}
    end
  end

  @doc """
  List the P2P nodes supporting filtering by availability and authorization

  Options:
  - availability: define the level of reachability for the node to retrieve.
      - `global` means the node have been discovered as online during the beacon chain summary.
      - `local` means `the node have exchanged successfully for the last time
  - `authorized?`: determine if the node to retrieve must be an authorized one

  **Note**: this options can be overlapped to produce a more fined grained node selection
              (i.e authorized but only locally available)

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> [node] == MemTable.list_nodes()
      true

    Returns only the nodes which are globally available

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   available?: false
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3",
      ...>   available?: true
      ...> }
      iex> MemTable.add_node(node2)
      iex> [node2] == MemTable.list_nodes(availability: :global)
      true

    Returns only the nodes which are locally available

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   availability_history: <<0::1, 1::1>>
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3",
      ...>   availability_history: <<1::1, 1::1>>
      ...> }
      iex> MemTable.add_node(node2)
      iex> [node2] == MemTable.list_nodes(availability: :local)
      true

   Returns only the nodes which are authorized

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3",
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...> }
      iex> MemTable.add_node(node2)
      iex> [node2] == MemTable.list_nodes(authorized?: true)
      true
  """
  @spec list_nodes(availability: :global | :local, authorized?: boolean) :: list(Node.t())
  def list_nodes(opts \\ []) do
    availability = Keyword.get(opts, :availability)
    authorized? = Keyword.get(opts, :authorized?, false)

    do_list_nodes(authorized?: authorized?, availability: availability)
  end

  defp do_list_nodes(authorized?: true, availability: :local) do
    :ets.foldl(
      fn {key, authorization_date}, acc ->
        [res] = :ets.lookup(@discovery_table, key)
        node = Node.cast(res)

        if Node.locally_available?(node) do
          [Node.authorize(node, authorization_date) | acc]
        else
          acc
        end
      end,
      [],
      @authorized_nodes_table
    )
  end

  defp do_list_nodes(authorized?: true, availability: :global) do
    :ets.foldl(
      fn {key, authorization_date}, acc ->
        if :ets.member(@availability_lookup_table, key) do
          [res] = :ets.lookup(@discovery_table, key)
          node = Node.cast(res)
          [Node.authorize(node, authorization_date) | acc]
        else
          acc
        end
      end,
      [],
      @authorized_nodes_table
    )
  end

  defp do_list_nodes(authorized?: true, availability: _) do
    :ets.foldl(
      fn {key, authorization_date}, acc ->
        [res] = :ets.lookup(@discovery_table, key)
        node = Node.cast(res)
        [Node.authorize(node, authorization_date) | acc]
      end,
      [],
      @authorized_nodes_table
    )
  end

  defp do_list_nodes(authorized?: _, availability: :global) do
    list_node_first_public_keys()
    |> Enum.filter(&:ets.member(@availability_lookup_table, &1))
    |> Enum.map(fn key ->
      [entry] = :ets.lookup(@discovery_table, key)

      entry
      |> Node.cast()
      |> toggle_node_authorization()
      |> Node.available()
    end)
  end

  defp do_list_nodes(authorized?: _, availability: :local) do
    :ets.foldl(
      fn entry, acc ->
        node = Node.cast(entry)

        if Node.locally_available?(node) do
          node =
            node
            |> toggle_node_authorization()
            |> toggle_node_availability()

          [node | acc]
        else
          acc
        end
      end,
      [],
      @discovery_table
    )
  end

  defp do_list_nodes(_) do
    :ets.foldl(
      fn entry, acc ->
        node =
          entry
          |> Node.cast()
          |> toggle_node_authorization()
          |> toggle_node_availability()

        [node | acc]
      end,
      [],
      @discovery_table
    )
  end

  @doc """
  List all the node first public keys

  ## Examples

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3"
      ...> }
      iex> MemTable.add_node(node2)
      iex> MemTable.list_node_first_public_keys()
      ["key1", "key3"]
  """
  @spec list_node_first_public_keys() :: list(Crypto.key())
  def list_node_first_public_keys do
    ets_table_keys(@discovery_table)
  end

  @doc """
  List the authorized node public keys

  ## Examples

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3",
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...> }
      iex> MemTable.add_node(node2)
      iex> MemTable.list_authorized_public_keys()
      ["key3"]
  """
  @spec list_authorized_public_keys() :: list(Crypto.key())
  def list_authorized_public_keys do
    ets_table_keys(@authorized_nodes_table)
  end

  @doc """
  Mark the node as authorized.

  ## Examples

      iex> MemTable.start_link()
      iex> :ok = MemTable.add_node(%Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key1",
      ...> })
      iex> :ok = MemTable.authorize_node("key1", ~U[2020-10-22 23:45:41.181903Z])
      iex> MemTable.list_authorized_public_keys()
      ["key1"]
  """
  @spec authorize_node(first_public_key :: Crypto.key(), authorization_date :: DateTime.t()) ::
          :ok
  def authorize_node(first_public_key, date = %DateTime{}) when is_binary(first_public_key) do
    if :ets.member(@authorized_nodes_table, first_public_key) do
      :ok
    else
      true = :ets.insert(@authorized_nodes_table, {first_public_key, date})
      Logger.info("New authorized node", node: Base.encode16(first_public_key))
      notify_node_update(first_public_key)
    end
  end

  @doc """
  Reset the authorized nodes

  ## Examples

      iex> MemTable.start_link()
      iex> :ok = MemTable.add_node(%Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key1",
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:45:41.181903Z]
      ...> })
      iex> :ok  = MemTable.reset_authorized_nodes()
      iex> MemTable.list_authorized_public_keys()
      []
  """
  @spec reset_authorized_nodes() :: :ok
  def reset_authorized_nodes do
    true = :ets.delete_all_objects(@authorized_nodes_table)
    Logger.info("Renew authorized nodes")

    Enum.each(list_node_first_public_keys(), &notify_node_update/1)
    :ok
  end

  @doc """
  Return the first public key from a node key

  If the given key is the first one, it will returns
  Otherwise a lookup table is used to match the last key from the first key

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> MemTable.get_first_node_key("key1")
      "key1"

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> MemTable.get_first_node_key("key2")
      "key1"
  """
  @spec get_first_node_key(Crypto.key()) :: Crypto.key()
  def get_first_node_key(key) when is_binary(key) do
    case :ets.lookup(@nodes_key_lookup_table, key) do
      [] ->
        key

      [{_, first_key}] ->
        first_key
    end
  end

  @doc """
  Mark the node as globally available

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_available("key1")
      iex> {:ok, %Node{available?: true}} = MemTable.get_node("key1")
  """
  @spec set_node_available(Crypto.key()) :: :ok
  def set_node_available(first_public_key) when is_binary(first_public_key) do
    true = :ets.insert(@availability_lookup_table, {first_public_key})
    Logger.info("Node globally available", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key)
    :ok
  end

  @doc """
  Mark the node globally unavailable

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_available("key1")
      iex> :ok = MemTable.set_node_unavailable("key1")
      iex> {:ok, %Node{available?: false}} = MemTable.get_node("key1")
  """
  @spec set_node_unavailable(Crypto.key()) :: :ok
  def set_node_unavailable(first_public_key) when is_binary(first_public_key) do
    :ets.delete(@availability_lookup_table, first_public_key)
    Logger.info("Node globally unavailable", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key)
    :ok
  end

  @doc """
  Set the node as available if previously flagged as offline

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   availability_history: <<0::1>>
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.increase_node_availability("key1")
      iex> {:ok, %Node{availability_history: <<1::1, 0::1>>}} = MemTable.get_node("key1")
  """
  @spec increase_node_availability(first_public_key :: Crypto.key()) :: :ok
  def increase_node_availability(first_public_key) when is_binary(first_public_key) do
    if :ets.member(@discovery_table, first_public_key) do
      case :ets.lookup_element(@discovery_table, first_public_key, 8) do
        <<1::1, _::bitstring>> ->
          :ok

        <<0::1, _::bitstring>> = history ->
          new_history = <<1::1, history::bitstring>>
          true = :ets.update_element(@discovery_table, first_public_key, {8, new_history})
          Logger.info("P2P availability increase", node: Base.encode16(first_public_key))
          notify_node_update(first_public_key)
          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Set the node as unavailable if previously flagged as online

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   availability_history: <<1::1>>
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.decrease_node_availability("key1")
      iex> {:ok, %Node{availability_history: <<0::1, 1::1>>}} = MemTable.get_node("key1")
  """
  @spec decrease_node_availability(first_public_key :: Crypto.key()) :: :ok
  def decrease_node_availability(first_public_key) when is_binary(first_public_key) do
    if :ets.member(@discovery_table, first_public_key) do
      case :ets.lookup_element(@discovery_table, first_public_key, 8) do
        <<0::1, _::bitstring>> ->
          :ok

        <<1::1, _::bitstring>> = history ->
          new_history = <<0::1, history::bitstring>>
          true = :ets.update_element(@discovery_table, first_public_key, {8, new_history})
          Logger.info("P2P availability decrease", node: Base.encode16(first_public_key))
          notify_node_update(first_public_key)
          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Update the average availability of the node and reset the history

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   average_availability: 0.4
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.update_node_average_availability("key1", 0.8)
      iex> {:ok, %Node{average_availability: 0.8}} = MemTable.get_node("key1")
  """
  @spec update_node_average_availability(
          first_public_key :: Crypto.key(),
          average_availability :: float()
        ) :: :ok
  def update_node_average_availability(first_public_key, avg_availability)
      when is_binary(first_public_key) and is_float(avg_availability) do
    true =
      :ets.update_element(@discovery_table, first_public_key, [{7, avg_availability}, {8, <<>>}])

    Logger.info("New average availability: #{avg_availability}}",
      node: Base.encode16(first_public_key)
    )

    notify_node_update(first_public_key)
    :ok
  end

  @doc """
  Update the network patch

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   network_patch: "AAA"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.update_node_network_patch("key1", "3FC")
      iex> {:ok, %Node{network_patch: "3FC"}} = MemTable.get_node("key1")
  """
  @spec update_node_network_patch(first_public_key :: Crypto.key(), network_patch :: binary()) ::
          :ok
  def update_node_network_patch(first_public_key, patch)
      when is_binary(first_public_key) and is_binary(patch) do
    true = :ets.update_element(@discovery_table, first_public_key, [{6, patch}])
    Logger.info("New network patch: #{patch}}", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key)
    :ok
  end

  def toggle_node_authorization(node = %Node{first_public_key: first_public_key}) do
    case :ets.lookup(@authorized_nodes_table, first_public_key) do
      [] ->
        Node.remove_authorization(node)

      [{_, authorization_date}] ->
        Node.authorize(node, authorization_date)
    end
  end

  def toggle_node_availability(node = %Node{first_public_key: first_public_key}) do
    if :ets.member(@availability_lookup_table, first_public_key) do
      Node.available(node)
    else
      Node.unavailable(node)
    end
  end

  defp ets_table_keys(table_name) do
    first_key = :ets.first(table_name)
    ets_table_keys(table_name, first_key, [first_key])
  end

  defp ets_table_keys(_table_name, :"$end_of_table", [:"$end_of_table" | acc]) do
    acc
  end

  defp ets_table_keys(table_name, key, acc) do
    next_key = :ets.next(table_name, key)
    ets_table_keys(table_name, next_key, [next_key | acc])
  end

  defp notify_node_update(public_key) do
    case get_node(public_key) do
      {:ok, node} ->
        PubSub.notify_node_update(node)

      _ ->
        Logger.error("Node not found")
        :ok
    end
  end
end
