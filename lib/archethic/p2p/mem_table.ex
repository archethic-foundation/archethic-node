defmodule Archethic.P2P.MemTable do
  @moduledoc false

  @discovery_table :archethic_node_discovery
  @nodes_key_lookup_table :archethic_node_keys
  @authorized_nodes_table :archethic_authorized_nodes

  alias Archethic.Crypto

  alias Archethic.P2P.Node

  alias Archethic.PubSub

  use GenServer
  @vsn Mix.Project.config()[:version]

  require Logger

  @discovery_index_position [
    first_public_key: 1,
    last_public_key: 2,
    ip: 3,
    port: 4,
    http_port: 5,
    geo_patch: 6,
    network_patch: 7,
    average_availability: 8,
    availability_history: 9,
    enrollment_date: 10,
    transport: 11,
    reward_address: 12,
    last_address: 13,
    origin_public_key: 14,
    synced?: 15,
    last_update_date: 16,
    available?: 17,
    availability_update: 18
  ]

  @doc """
  Initialize the memory tables for the P2P view
  """
  @spec start_link([]) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@discovery_table, [:set, :named_table, :public, read_concurrency: true])
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
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   geo_patch: "AFZ",
      ...>   network_patch: "AAA",
      ...>   availability_history: <<1::1, 1::1>>,
      ...>   average_availability: 0.9,
      ...>   available?: true,
      ...>   synced?: true,
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   enrollment_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   last_update_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   availability_update: ~U[2020-10-22 23:19:45.797109Z],
      ...>   transport: :tcp,
      ...>   reward_address: <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182,
      ...>     87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
      ...>   last_address: <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173,
      ...>     88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
      ...>   origin_public_key: <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
      ...>    185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>
      ...> }
      iex> :ok = MemTable.add_node(node)
      iex> {
      ...>   :ets.tab2list(:archethic_node_discovery),
      ...>   :ets.tab2list(:archethic_authorized_nodes),
      ...>   :ets.tab2list(:archethic_node_keys)
      ...>  }
      {
        # Discovery table
        [{
          "key1", "key2", {127, 0, 0, 1}, 3000, 4000, "AFZ", "AAA", 0.9, <<1::1, 1::1>>, ~U[2020-10-22 23:19:45.797109Z], :tcp,
          <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182,
            87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
          <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173,
            88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
          <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
            185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>, true, ~U[2020-10-22 23:19:45.797109Z],
            true, ~U[2020-10-22 23:19:45.797109Z]
        }],
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
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2",
      ...>   geo_patch: "AFZ",
      ...>   network_patch: "AAA",
      ...>   availability_history: <<1::1, 1::1>>,
      ...>   average_availability: 0.9,
      ...>   available?: true,
      ...>   synced?: true,
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   enrollment_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   last_update_date: ~U[2020-10-22 23:19:45.797109Z],
      ...>   availability_update: ~U[2020-10-22 23:19:45.797109Z],
      ...>   transport: :tcp,
      ...>   reward_address: <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182,
      ...>     87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
      ...>   last_address: <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173,
      ...>     88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
      ...>   origin_public_key: <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
      ...>    185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>
      ...> }
      iex> :ok = MemTable.add_node(node)
      iex> :ok = MemTable.add_node(%Node{
      ...>   ip: {80, 20, 10, 122},
      ...>   port: 5000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key5",
      ...>   average_availability: 90,
      ...>   availability_history: <<1::1, 1::1>>,
      ...>   last_update_date: ~U[2020-10-22 23:20:45.797109Z],
      ...>   synced?: false,
      ...>   availability_update: ~U[2020-10-23 23:20:45.797109Z],
      ...>   available?: false,
      ...>   transport: :sctp,
      ...>   reward_address: <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182,
      ...>     87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
      ...>   last_address: <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173,
      ...>     88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
      ...>   origin_public_key: <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
      ...>    185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>
      ...>  })
      iex> :ets.lookup(:archethic_node_discovery, "key1")
      [{
        "key1",
        "key5",
        {80, 20, 10, 122},
        5000,
        4000,
        "AFZ",
        "AAA",
        90,
        <<1::1, 1::1>>,
        ~U[2020-10-22 23:19:45.797109Z],
        :sctp,
        <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182, 87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
        <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173, 88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
        <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
          185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>,
        false,
        ~U[2020-10-22 23:20:45.797109Z],
        false,
        ~U[2020-10-23 23:20:45.797109Z]
      }]
  """
  @spec add_node(Node.t()) :: :ok
  def add_node(
        node = %Node{
          first_public_key: first_public_key,
          last_public_key: last_public_key,
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
         http_port: http_port,
         geo_patch: geo_patch,
         network_patch: network_patch,
         enrollment_date: enrollment_date,
         synced?: synced?,
         average_availability: average_availability,
         availability_history: availability_history,
         transport: transport,
         reward_address: reward_address,
         last_address: last_address,
         origin_public_key: origin_public_key,
         last_update_date: last_update_date,
         available?: available?,
         availability_update: availability_update
       }) do
    availability_history =
      if first_public_key == Crypto.first_node_public_key(),
        do: <<1::1>>,
        else: availability_history

    :ets.insert(
      @discovery_table,
      {first_public_key, last_public_key, ip, port, http_port, geo_patch, network_patch,
       average_availability, availability_history, enrollment_date, transport, reward_address,
       last_address, origin_public_key, synced?, last_update_date, available?,
       availability_update}
    )
  end

  defp update_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         ip: ip,
         port: port,
         http_port: http_port,
         geo_patch: geo_patch,
         network_patch: network_patch,
         average_availability: average_availability,
         enrollment_date: enrollment_date,
         synced?: synced?,
         transport: transport,
         reward_address: reward_address,
         last_address: last_address,
         origin_public_key: origin_public_key,
         last_update_date: timestamp,
         available?: available?,
         availability_update: availability_update
       }) do
    if available?,
      do: set_node_available(first_public_key, availability_update),
      else: set_node_unavailable(first_public_key, availability_update)

    changes = [
      {Keyword.fetch!(@discovery_index_position, :last_public_key), last_public_key},
      {Keyword.fetch!(@discovery_index_position, :reward_address), reward_address},
      {Keyword.fetch!(@discovery_index_position, :last_address), last_address},
      {Keyword.fetch!(@discovery_index_position, :origin_public_key), origin_public_key}
    ]

    # We change connection informations only if these infos are newer than the actual ones
    timestamp_pos = Keyword.fetch!(@discovery_index_position, :last_update_date)
    last_update_date = :ets.lookup_element(@discovery_table, first_public_key, timestamp_pos)

    changes =
      if DateTime.compare(timestamp, last_update_date) != :lt do
        changes ++
          [
            {Keyword.fetch!(@discovery_index_position, :ip), ip},
            {Keyword.fetch!(@discovery_index_position, :port), port},
            {Keyword.fetch!(@discovery_index_position, :http_port), http_port},
            {Keyword.fetch!(@discovery_index_position, :transport), transport},
            {timestamp_pos, timestamp}
          ]
      else
        changes
      end

    changes =
      if geo_patch != nil do
        [{Keyword.fetch!(@discovery_index_position, :geo_patch), geo_patch} | changes]
      else
        changes
      end

    changes =
      if network_patch != nil do
        [{Keyword.fetch!(@discovery_index_position, :network_patch), network_patch} | changes]
      else
        changes
      end

    changes =
      if average_availability != nil do
        [
          {Keyword.fetch!(@discovery_index_position, :average_availability), average_availability}
          | changes
        ]
      else
        changes
      end

    changes =
      if enrollment_date != nil do
        [{Keyword.fetch!(@discovery_index_position, :enrollment_date), enrollment_date} | changes]
      else
        changes
      end

    changes =
      if synced? != nil do
        [{Keyword.fetch!(@discovery_index_position, :synced?), synced?} | changes]
      else
        changes
      end

    :ets.update_element(@discovery_table, first_public_key, changes)
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
      ...>   http_port: 4000,
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
      ...>   http_port: 4000,
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

        {:ok, node}
    end
  end

  @doc """
  List the P2P nodes

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> [node] == MemTable.list_nodes()
      true
  """
  @spec list_nodes() :: list(Node.t())
  def list_nodes do
    :ets.foldl(
      fn entry, acc ->
        node =
          entry
          |> Node.cast()
          |> toggle_node_authorization()

        [node | acc]
      end,
      [],
      @discovery_table
    )
  end

  @doc """
  List the authorized nodes

  ## Examples

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3",
      ...>   authorized?: true,
      ...>   available?: true,
      ...>   authorization_date: ~U[2020-10-22 23:19:45.797109Z],
      ...> }
      iex> MemTable.add_node(node2)
      iex> [node2] == MemTable.authorized_nodes()
      true
  """
  @spec authorized_nodes() :: list(Node.t())
  def authorized_nodes do
    :ets.foldl(
      fn {key, authorization_date}, acc ->
        [res] = :ets.lookup(@discovery_table, key)

        node =
          res
          |> Node.cast()
          |> Node.authorize(authorization_date)

        [node | acc]
      end,
      [],
      @authorized_nodes_table
    )
  end

  @doc """
  List the nodes whicih are globally available

  ## Examples

      iex> MemTable.start_link()
      iex> node1 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key3",
      ...>   last_public_key: "key3",
      ...>   available?: true,
      ...>   authorized?: true,
      ...>   authorization_date: DateTime.utc_now()
      ...> }
      iex> MemTable.add_node(node2)
      iex> [node2] == MemTable.available_nodes()
      true
  """
  @spec available_nodes() :: list(Node.t())
  def available_nodes do
    availability_pos = Keyword.fetch!(@discovery_index_position, :available?) - 1

    :ets.foldl(
      fn
        res, acc when elem(res, availability_pos) == true ->
          node =
            res
            |> Node.cast()
            |> toggle_node_authorization()

          [node | acc]

        _, acc ->
          acc
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
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
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
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node1)
      iex> node2 = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
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
      ...>   http_port: 4000,
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
    Logger.info("New authorized node", node: Base.encode16(first_public_key))

    if !:ets.member(@authorized_nodes_table, first_public_key) do
      true = :ets.insert(@authorized_nodes_table, {first_public_key, date})
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
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key1",
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-10-22 23:45:41.181903Z]
      ...> })
      iex> :ok  = MemTable.unauthorize_node("key1")
      iex> MemTable.list_authorized_public_keys()
      []
  """
  @spec unauthorize_node(Crypto.key()) :: :ok
  def unauthorize_node(first_public_key) when is_binary(first_public_key) do
    true = :ets.delete(@authorized_nodes_table, first_public_key)
    Logger.info("Unauthorized node", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key)
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
      ...>   http_port: 4000,
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
      ...>   http_port: 4000,
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
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_available("key1", ~U[2020-10-22 23:45:41Z])
      iex> {:ok, %Node{available?: true, availability_update: ~U[2020-10-22 23:45:41Z]}} = MemTable.get_node("key1")
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_available("key1", ~U[2020-10-23 23:45:41Z])
      iex> {:ok, %Node{available?: true, availability_update: ~U[2020-10-23 23:45:41Z]}} = MemTable.get_node("key1")
  """
  @spec set_node_available(Crypto.key(), DateTime.t()) :: :ok
  def set_node_available(first_public_key, availability_update)
      when is_binary(first_public_key) do
    Logger.info("Node globally available", node: Base.encode16(first_public_key))

    # When a node bootstrap, before starting its self repair, it load the current p2p view of the network.
    # But then when the self repair occurs, the node needs to know the p2p view at the summary time so we need to update
    # the node availability update to match the one it was at the time of the current repairing summary.
    # So if a node wants to update a node already available but with a lower availability_update, it means that 
    # the node is performing a self repair from the bootstrap so we update the date

    availability_pos = Keyword.fetch!(@discovery_index_position, :available?)
    availability_update_pos = Keyword.fetch!(@discovery_index_position, :availability_update)

    already_available? = :ets.lookup_element(@discovery_table, first_public_key, availability_pos)

    availability_update_from_bootstrap? =
      :ets.lookup_element(@discovery_table, first_public_key, availability_update_pos)
      |> DateTime.compare(availability_update) == :gt

    if not already_available? or availability_update_from_bootstrap? do
      :ets.update_element(@discovery_table, first_public_key, [
        {availability_pos, true},
        {availability_update_pos, availability_update}
      ])

      notify_node_update(first_public_key)
    end

    :ok
  end

  @doc """
  Mark the node globally unavailable

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_available("key1", ~U[2020-10-22 23:45:41Z])
      iex> :ok = MemTable.set_node_unavailable("key1", ~U[2020-10-23 23:45:41Z])
      iex> {:ok, %Node{available?: false, availability_update: ~U[2020-10-23 23:45:41Z]}} = MemTable.get_node("key1")
  """
  @spec set_node_unavailable(Crypto.key(), DateTime.t()) :: :ok
  def set_node_unavailable(first_public_key, availability_update)
      when is_binary(first_public_key) do
    Logger.info("Node globally unavailable", node: Base.encode16(first_public_key))

    availability_pos = Keyword.fetch!(@discovery_index_position, :available?)

    if :ets.lookup_element(@discovery_table, first_public_key, availability_pos) do
      availability_update_pos = Keyword.fetch!(@discovery_index_position, :availability_update)

      :ets.update_element(@discovery_table, first_public_key, {availability_pos, false})

      :ets.update_element(
        @discovery_table,
        first_public_key,
        {availability_update_pos, availability_update}
      )

      notify_node_update(first_public_key)
    end

    :ok
  end

  @doc """
  Mark the node synced

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_synced("key1")
      iex> {:ok, %Node{synced?: true}} = MemTable.get_node("key1")
  """
  @spec set_node_synced(Crypto.key()) :: :ok
  def set_node_synced(first_public_key) when is_binary(first_public_key) do
    synced_pos = Keyword.fetch!(@discovery_index_position, :synced?)
    :ets.update_element(@discovery_table, first_public_key, {synced_pos, true})
    Logger.info("Node synced", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key)
    :ok
  end

  @doc """
  Mark the node unsynced

  ## Examples

      iex> MemTable.start_link()
      iex> node = %Node{
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   first_public_key: "key1",
      ...>   last_public_key: "key2"
      ...> }
      iex> MemTable.add_node(node)
      iex> :ok = MemTable.set_node_synced("key1")
      iex> :ok = MemTable.set_node_unsynced("key1")
      iex> {:ok, %Node{synced?: false}} = MemTable.get_node("key1")
  """
  @spec set_node_unsynced(Crypto.key()) :: :ok
  def set_node_unsynced(first_public_key) when is_binary(first_public_key) do
    synced_pos = Keyword.fetch!(@discovery_index_position, :synced?)
    :ets.update_element(@discovery_table, first_public_key, {synced_pos, false})
    Logger.info("Node unsynced", node: Base.encode16(first_public_key))
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
      ...>   http_port: 4000,
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
      tuple_pos = Keyword.fetch!(@discovery_index_position, :availability_history)

      case :ets.lookup_element(@discovery_table, first_public_key, tuple_pos) do
        <<1::1, _::bitstring>> ->
          :ok

        <<0::1, _::bitstring>> = history ->
          new_history = <<1::1, history::bitstring>>
          true = :ets.update_element(@discovery_table, first_public_key, {tuple_pos, new_history})
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
      ...>   http_port: 4000,
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
      tuple_pos = Keyword.fetch!(@discovery_index_position, :availability_history)

      case :ets.lookup_element(@discovery_table, first_public_key, tuple_pos) do
        <<0::1, _::bitstring>> ->
          :ok

        <<1::1, _::bitstring>> = history ->
          new_history = <<0::1, history::bitstring>>

          true = :ets.update_element(@discovery_table, first_public_key, {tuple_pos, new_history})

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
      ...>   http_port: 4000,
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
    avg_availability_pos = Keyword.fetch!(@discovery_index_position, :average_availability)
    availability_history_pos = Keyword.fetch!(@discovery_index_position, :availability_history)

    <<last_history::1, _rest::bitstring>> =
      :ets.lookup_element(@discovery_table, first_public_key, availability_history_pos)

    true =
      :ets.update_element(@discovery_table, first_public_key, [
        {avg_availability_pos, avg_availability},
        {availability_history_pos, <<last_history::1>>}
      ])

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
      ...>   http_port: 4000,
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
    tuple_pos = Keyword.fetch!(@discovery_index_position, :network_patch)
    true = :ets.update_element(@discovery_table, first_public_key, [{tuple_pos, patch}])
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
