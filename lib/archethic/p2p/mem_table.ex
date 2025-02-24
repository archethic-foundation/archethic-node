defmodule Archethic.P2P.MemTable do
  @moduledoc false

  @discovery_table :archethic_node_discovery
  @nodes_key_lookup_table :archethic_node_keys
  @authorized_nodes_table :archethic_authorized_nodes

  alias Archethic.DB.EmbeddedImpl.P2PView
  alias Archethic.Crypto

  alias Archethic.P2P.Node
  alias Archethic.P2P.P2PView

  alias Archethic.PubSub

  use GenServer
  @vsn 1

  require Logger

  @discovery_index_position [
    first_public_key: 1,
    last_public_key: 2,
    ip: 3,
    port: 4,
    http_port: 5,
    # geo_patch: 6,
    network_patch: 7,
    # average_availability: 8,
    enrollment_date: 9,
    transport: 10,
    reward_address: 11,
    last_address: 12,
    origin_public_key: 13,
    synced?: 14,
    last_update_date: 15,
    # available?: 16,
    # availability_update: 17,
    mining_public_key: 18
  ]

  # TODO integrate p2pview to take its data into account
  # TODO remove p2pview properties from @authorized_nodes_table
  # TODO update ets tables on migration
  # TODO update ets table on MemTableLoader load
  # TODO update ets table on p2p.nodeconfig.config

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

    P2PView.start_link()

    {:ok, []}
  end

  @doc """
  Add a node into the P2P view.

  If a node already exists with the first public key, the P2P information will be updated.
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
      update_p2p_view(node)
      Logger.info("Node update", node: Base.encode16(first_public_key))
      Logger.debug("Update info: #{inspect(node)}", node: Base.encode16(first_public_key))
    else
      insert_p2p_discovery(node)
      insert_p2p_view(node)
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

  defp insert_p2p_view(%Node{
         first_public_key: first_public_key,
         geo_patch: geo_patch,
         # TODO Utiliser geo_patch_update ?
         #  geo_patch_update: geo_patch_update,
         average_availability: average_availability,
         available?: available?,
         availability_update: availability_update
       }) do
    P2PView.add_node(
      %P2PView{
        geo_patch: geo_patch,
        available?: available?,
        avg_availability: average_availability
      },
      availability_update,
      &node_index_at_timestamp(first_public_key, &1)
    )
  end

  defp insert_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         mining_public_key: mining_public_key,
         ip: ip,
         port: port,
         http_port: http_port,
         network_patch: network_patch,
         enrollment_date: enrollment_date,
         synced?: synced?,
         transport: transport,
         reward_address: reward_address,
         last_address: last_address,
         origin_public_key: origin_public_key,
         last_update_date: last_update_date
       }) do
    :ets.insert(
      @discovery_table,
      {first_public_key, last_public_key, ip, port, http_port, nil, network_patch, nil,
       enrollment_date, transport, reward_address, last_address, origin_public_key, synced?,
       last_update_date, nil, nil, mining_public_key}
    )
  end

  defp update_p2p_view(%Node{
         first_public_key: first_public_key,
         geo_patch: geo_patch,
         geo_patch_update: geo_patch_update,
         average_availability: average_availability,
         available?: available?,
         availability_update: availability_update
       }) do
    P2PView.update_node(
      [
        geo_patch: geo_patch
      ],
      geo_patch_update,
      &node_index_at_timestamp(first_public_key, &1)
    )

    P2PView.update_node(
      [
        avg_availability: average_availability,
        available?: available?
      ],
      availability_update,
      &node_index_at_timestamp(first_public_key, &1)
    )
  end

  defp update_p2p_view(changes, first_public_key, timestamp) when is_list(changes) do
    P2PView.update_node(
      changes,
      timestamp,
      &node_index_at_timestamp(first_public_key, &1)
    )
  end

  defp get_p2p_view(first_public_key, timestamp) do
    P2PView.get_p2p_view(timestamp, node_index_at_timestamp(first_public_key, timestamp))
  end

  defp update_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         mining_public_key: mining_public_key,
         ip: ip,
         port: port,
         http_port: http_port,
         network_patch: network_patch,
         enrollment_date: enrollment_date,
         synced?: synced?,
         transport: transport,
         reward_address: reward_address,
         last_address: last_address,
         origin_public_key: origin_public_key,
         last_update_date: timestamp
       }) do
    changes = [
      {Keyword.fetch!(@discovery_index_position, :last_public_key), last_public_key},
      {Keyword.fetch!(@discovery_index_position, :reward_address), reward_address},
      {Keyword.fetch!(@discovery_index_position, :last_address), last_address},
      {Keyword.fetch!(@discovery_index_position, :origin_public_key), origin_public_key},
      {Keyword.fetch!(@discovery_index_position, :ip), ip},
      {Keyword.fetch!(@discovery_index_position, :port), port},
      {Keyword.fetch!(@discovery_index_position, :http_port), http_port},
      {Keyword.fetch!(@discovery_index_position, :transport), transport},
      {Keyword.fetch!(@discovery_index_position, :last_update_date), timestamp},
      {Keyword.fetch!(@discovery_index_position, :mining_public_key), mining_public_key}
    ]

    changes =
      if network_patch != nil do
        [{Keyword.fetch!(@discovery_index_position, :network_patch), network_patch} | changes]
      else
        changes
      end

    changes =
      if enrollment_date != nil do
        [
          {Keyword.fetch!(@discovery_index_position, :enrollment_date), enrollment_date}
          | changes
        ]
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
  """
  # TODO add date en parametre. retourner tout les noeuds ou enrollment_date < date
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
  """

  # TODO update nodes properties using p2pView

  @spec authorized_nodes() :: list(Node.t())
  def authorized_nodes do
    :ets.foldl(
      fn {key, authorization_date}, acc ->
        [res] = :ets.lookup(@discovery_table, key)

        p2pview = P2PView.get_summary(authorization_date)

        node =
          res
          |> Node.cast(p2pview)
          |> Node.authorize(authorization_date)

        [node | acc]
      end,
      [],
      @authorized_nodes_table
    )
  end

  @doc """
  List the nodes which are globally available
  """
  @spec available_nodes(DateTime.t()) :: list(Node.t())
  def available_nodes(timestamp) do
    P2PView.get_summary(timestamp)
    |> Enum.filter(fn p2pview -> p2pView.available? == true end)
    |> Enum.map(fn p2pview ->
      :ets.lookup_element(@discovery_table, p2pview.)
    end)
    availability_pos = Keyword.fetch!(@discovery_index_position, :available?) - 1

    :ets.foldl(
      fn
        res, acc when elem(res, availability_pos) == true ->
          node =
            res
            |> Node.cast()
            # TODO qu'est ce que ca fait la ?
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
  """
  @spec list_node_first_public_keys() :: list(Crypto.key())
  def list_node_first_public_keys do
    ets_table_keys(@discovery_table)
  end

  @doc """
  List the authorized node public keys
  """
  @spec list_authorized_public_keys() :: list(Crypto.key())
  def list_authorized_public_keys do
    ets_table_keys(@authorized_nodes_table)
  end

  @doc """
  Mark the node as authorized.
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
  """
  @spec set_node_available(Crypto.key(), DateTime.t()) :: :ok
  def set_node_available(first_public_key, availability_update)
      when is_binary(first_public_key) do
    Logger.info("Node globally available", node: Base.encode16(first_public_key))

    # availability_pos = Keyword.fetch!(@discovery_index_position, :available?)
    # availability_update_pos = Keyword.fetch!(@discovery_index_position, :availability_update)

    # :ets.update_element(@discovery_table, first_public_key, [
    #   {availability_pos, true},
    #   {availability_update_pos, availability_update}
    # ])

    update_p2p_view(
      [available: true],
      first_public_key,
      availability_update
    )

    notify_node_update(first_public_key)

    :ok
  end

  defp node_index_at_timestamp(first_public_key, timestamp) do
    # :ets.match_object(
    #   :nodes,
    #   {:"$1", :_, :_, :_, :_, :_, :_, :_, :"$2", :_, :_, :_, :_, :_, :_, :_, :_, :_}
    # ) |>

    # TODO utiliser @discovery_index_position pour créer le `match_spec`
    # availability_pos = Keyword.fetch!(@discovery_index_position, :available?) - 1

    # :ets.foldl(
    #   fn
    #     res, acc when elem(res, availability_pos) == true ->
    #       node =
    #         res
    #         |> Node.cast()
    #         |> toggle_node_authorization()

    #       [node | acc]

    #     _, acc ->
    #       acc
    #   end,
    #   [],
    #   @discovery_table
    # )

    :ets.select(
      :nodes,
      [
        {
          {:"$1", :_, :_, :_, :_, :_, :_, :_, :"$2", :_, :_, :_, :_, :_, :_, :_, :_, :_},
          [],
          [{{:"$1", :"$2"}}]
        }
      ]
    )
    |> Enum.filter(fn {_, enrollment_date} -> enrollment_date <= timestamp end)
    |> Enum.map(fn {first_public_key, _} -> first_public_key end)
    |> Enum.sort()
    |> Enum.find_index(fn node_first_public_key -> node_first_public_key == first_public_key end)
  end

  @doc """
  Mark the node globally unavailable
  """
  @spec set_node_unavailable(Crypto.key(), DateTime.t()) :: :ok
  def set_node_unavailable(first_public_key, availability_update)
      when is_binary(first_public_key) do
    Logger.info("Node globally unavailable", node: Base.encode16(first_public_key))

    # availability_pos = Keyword.fetch!(@discovery_index_position, :available?)
    # availability_update_pos = Keyword.fetch!(@discovery_index_position, :availability_update)

    # :ets.update_element(@discovery_table, first_public_key, [
    #   {availability_pos, false},
    #   {availability_update_pos, availability_update}
    # ])
    update_p2p_view(
      [available: false],
      first_public_key,
      availability_update
    )

    notify_node_update(first_public_key)

    :ok
  end

  @doc """
  Mark the node synced
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
  Update the average availability of the node and reset the history
  """
  @spec update_node_average_availability(
          first_public_key :: Crypto.key(),
          average_availability :: float(),
          timestamp :: DateTime.t()
        ) :: :ok
  def update_node_average_availability(first_public_key, avg_availability, timestamp)
      when is_binary(first_public_key) and is_float(avg_availability) do
    # avg_availability_pos = Keyword.fetch!(@discovery_index_position, :average_availability)

    update_p2p_view([avg_availability: avg_availability], first_public_key, timestamp)
    # true =
    #   :ets.update_element(@discovery_table, first_public_key, [
    #     {avg_availability_pos, avg_availability}
    #   ])

    Logger.info("New average availability: #{avg_availability}}",
      node: Base.encode16(first_public_key)
    )

    notify_node_update(first_public_key)
    :ok
  end

  @doc """
  Update the network patch
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
