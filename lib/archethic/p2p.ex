defmodule Archethic.P2P do
  @moduledoc """
  Handle P2P node discovery and messaging
  """
  alias Archethic.{Crypto, TaskSupervisor, TransactionChain}

  alias Archethic.{TransactionChain.Transaction, Utils}

  alias __MODULE__.{BootstrappingSeeds, Client, GeoPatch, MemTable, MemTableLoader, Message, Node}

  alias __MODULE__.Message.NodeList
  alias __MODULE__.Message.ListNodes

  require Logger

  @type supported_transport :: :tcp

  @doc """
  Return the list of supported transport implementation
  """
  @spec supported_transports() :: list(supported_transport())
  def supported_transports, do: [:tcp]

  @doc """
  Compute a geographical patch (zone) from an IP
  """
  @spec get_geo_patch(:inet.ip_address()) :: binary()
  defdelegate get_geo_patch(ip), to: GeoPatch, as: :from_ip

  @doc """
  Get range of longitude / latitude coordinates from geographical patch
  """
  @spec get_coord_from_geo_patch(binary()) :: {{float(), float()}, {float(), float()}}
  defdelegate get_coord_from_geo_patch(geo_patch), to: GeoPatch, as: :to_coordinates

  @doc """
  Register a node and establish a connection with
  """
  @spec add_and_connect_node(Node.t()) :: :ok
  def add_and_connect_node(node = %Node{first_public_key: first_public_key}) do
    :ok = MemTable.add_node(node)
    node = get_node_info!(first_public_key)
    do_connect_node(node)
  end

  @doc """
  Establish a connection on a list of node in parallel
  This function wait for the connections to be established
  timeout for connection is 5 sec
  """
  @spec connect_nodes(list(Node.t())) :: :ok
  def connect_nodes(nodes) do
    not_connected_nodes = Enum.reject(nodes, &node_connected?/1)

    Task.Supervisor.async_stream(
      TaskSupervisor,
      not_connected_nodes,
      fn node = %Node{first_public_key: first_public_key} ->
        do_connect_node(node, self())

        receive do
          :connected ->
            :ok

          {:error, reason} ->
            Logger.warning("First connection attempt failed for #{inspect(reason)}",
              node: Base.encode16(first_public_key)
            )
        end
      end,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  defp do_connect_node(
         %Node{
           ip: ip,
           port: port,
           transport: transport,
           first_public_key: first_public_key
         },
         from \\ nil
       ) do
    if first_public_key == Crypto.first_node_public_key() do
      :ok
    else
      {:ok, _pid} = Client.new_connection(ip, port, transport, first_public_key, from)
      :ok
    end
  end

  @doc """
  Return true if the node connection is established
  """
  @spec node_connected?(node :: Node.t()) :: boolean()
  def node_connected?(%Node{first_public_key: first_public_key}) do
    if first_public_key == Crypto.first_node_public_key() do
      true
    else
      Client.connected?(first_public_key)
    end
  end

  @doc """
  Called by the telemetry poller
  """
  def nodes_connected_count() do
    nodes_connected =
      authorized_and_available_nodes()
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))
      |> Enum.filter(&node_connected?/1)
      |> Enum.count()

    :telemetry.execute(
      [:archethic, :p2p],
      %{nodes_connected: nodes_connected}
    )
  rescue
    _ ->
      # this will fail at startup because ETS table does not exist yet
      :ok
  end

  @doc """
  List the nodes registered.
  """
  @spec list_nodes() :: list(Node.t())
  defdelegate list_nodes, to: MemTable

  @doc """
  Fetch the list of nodes from close nodes
  """
  @spec fetch_nodes_list(authorized_and_available? :: boolean(), node_list :: list(Node.t())) ::
          {:ok, list(Node.t())} | {:error, :network_issue}
  def fetch_nodes_list(authorized_and_available?, nodes) do
    last_updated_nodes =
      fn new_node = %Node{
           first_public_key: public_key,
           last_update_date: update_date
         },
         acc ->
        previous_node =
          %Node{last_update_date: previous_update_date} = Map.get(acc, public_key, new_node)

        node =
          if DateTime.compare(update_date, previous_update_date) == :gt,
            do: new_node,
            else: previous_node

        Map.put(acc, public_key, node)
      end

    conflict_resolver = fn results ->
      nodes =
        Enum.flat_map(results, fn %NodeList{nodes: nodes} -> nodes end)
        |> Enum.reduce(%{}, fn node, acc -> last_updated_nodes.(node, acc) end)
        |> Map.values()

      %NodeList{nodes: nodes}
    end

    case quorum_read(
           nodes,
           %ListNodes{authorized_and_available?: authorized_and_available?},
           conflict_resolver
         ) do
      {:ok, %NodeList{nodes: nodes}} ->
        {:ok, nodes}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Return the list of available nodes
  """
  @spec available_nodes() :: list(Node.t())
  defdelegate available_nodes, to: MemTable

  @doc """
  Add a node first public key to the list of nodes globally available.
  """
  @spec set_node_globally_available(
          first_public_key :: Crypto.key(),
          availability_update :: DateTime.t()
        ) :: :ok
  def set_node_globally_available(first_public_key, availability_update) do
    unless available_node?(first_public_key) do
      MemTable.set_node_available(first_public_key, availability_update)
    end
  end

  @doc """
  Remove a node first public key to the list of nodes globally available.
  """
  @spec set_node_globally_unavailable(
          first_public_key :: Crypto.key(),
          availability_update :: DateTime.t()
        ) :: :ok
  def set_node_globally_unavailable(first_public_key, availability_update) do
    if available_node?(first_public_key) do
      MemTable.set_node_unavailable(first_public_key, availability_update)
    end
  end

  @doc """
  Add a node first public key to the list of nodes globally synced.
  """
  @spec set_node_globally_synced(first_public_key :: Crypto.key()) :: :ok
  defdelegate set_node_globally_synced(first_public_key), to: MemTable, as: :set_node_synced

  @doc """
  Add a node first public key to the list of nodes globally unsynced.
  """
  @spec set_node_globally_unsynced(first_public_key :: Crypto.key()) :: :ok
  defdelegate set_node_globally_unsynced(first_public_key), to: MemTable, as: :set_node_unsynced

  @doc """
  Set the node's average availability
  """
  @spec set_node_average_availability(first_public_key :: Crypto.key(), float()) :: :ok
  defdelegate set_node_average_availability(first_public_key, avg_availability),
    to: MemTable,
    as: :update_node_average_availability

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
  Determine if the node public key is authorized for the given datetime (default to now) or before if needed
  """
  @spec authorized_node?(Crypto.key(), date :: DateTime.t(), before? :: boolean()) :: boolean()
  def authorized_node?(
        node_public_key \\ Crypto.first_node_public_key(),
        datetime = %DateTime{} \\ DateTime.utc_now(),
        before? \\ false
      )
      when is_binary(node_public_key) and is_boolean(before?) do
    Utils.key_in_node_list?(authorized_nodes(datetime, before?), node_public_key)
  end

  @doc """
  Determine if the node public key is available
  """
  @spec available_node?(Crypto.key()) :: boolean()
  def available_node?(node_public_key \\ Crypto.first_node_public_key())
      when is_binary(node_public_key) do
    Utils.key_in_node_list?(available_nodes(), node_public_key)
  end

  @doc """
  Determine if the node public key is authorized and available for the given datetime (default to now) or before if needed
  """
  @spec authorized_and_available_node?(
          Crypto.key(),
          datetime :: DateTime.t(),
          before? :: boolean()
        ) :: boolean()
  def authorized_and_available_node?(
        node_public_key \\ Crypto.first_node_public_key(),
        datetime = %DateTime{} \\ DateTime.utc_now(),
        before? \\ false
      ) do
    Utils.key_in_node_list?(authorized_and_available_nodes(datetime, before?), node_public_key)
  end

  @doc """
  List the authorized nodes for the given datetime (default to now) or before if needed
  """
  @spec authorized_nodes(DateTime.t()) :: list(Node.t())
  def authorized_nodes(date \\ DateTime.utc_now(), before? \\ false) do
    nodes =
      MemTable.authorized_nodes()
      |> Enum.filter(fn %Node{authorization_date: authorization_date} ->
        if before?,
          do: DateTime.compare(authorization_date, date) == :lt,
          else: DateTime.compare(authorization_date, date) != :gt
      end)

    case nodes do
      [] ->
        # Only happen during bootstrap
        case get_first_enrolled_node() do
          nil -> []
          node -> [node]
        end

      nodes ->
        nodes
    end
  end

  @doc """
  List the authorized and available nodes
  before? is used in for self repair to not take in account the newly
  authorized nodes
  """
  @spec authorized_and_available_nodes(DateTime.t(), boolean()) :: list(Node.t())
  def authorized_and_available_nodes(date \\ DateTime.utc_now(), before? \\ false) do
    nodes =
      authorized_nodes(date, before?)
      |> Enum.filter(fn
        %Node{available?: true, availability_update: availability_update} ->
          if before?,
            do: DateTime.compare(date, availability_update) == :gt,
            else: DateTime.compare(date, availability_update) != :lt

        %Node{available?: false, availability_update: availability_update} ->
          if before?,
            do: DateTime.compare(date, availability_update) != :gt,
            else: DateTime.compare(date, availability_update) == :lt
      end)

    case nodes do
      [] ->
        # Only happen for init transactions so we take the first enrolled node
        case get_first_enrolled_node() do
          nil -> []
          node -> [node]
        end

      nodes ->
        nodes
    end
  end

  @doc """
  Return the first enrolled node
  """
  @spec get_first_enrolled_node() :: Node.t() | nil
  def get_first_enrolled_node() do
    list_nodes()
    |> Enum.reject(&(&1.enrollment_date == nil))
    |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime})
    |> List.first()
  end

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
    {:ok, node} = get_node_info(Crypto.first_node_public_key())
    node
  end

  @doc """
  Send a P2P message and fails if the message cannot be sent

  For mode details see `send_message/3`
  """
  @spec send_message!(Crypto.key() | Node.t(), Message.request(), timeout()) :: Message.response()
  def send_message!(node, message, timeout \\ 0)

  def send_message!(public_key, message, timeout) when is_binary(public_key) do
    public_key
    |> get_node_info!
    |> send_message!(message, timeout)
  end

  def send_message!(
        node = %Node{ip: ip, port: port},
        message,
        timeout
      ) do
    case Client.send_message(node, message, timeout) do
      {:ok, ref} ->
        ref

      {:error, reason} ->
        raise "Messaging error with #{:inet.ntoa(ip)}:#{port} - #{inspect(reason)}"
    end
  end

  @doc """
  Send a P2P message

  If the exchange fails, the node availability history will decrease
  and will be locally unavailable until the next exchange
  """
  @spec send_message(Crypto.key() | Node.t(), Message.request(), timeout()) ::
          {:ok, Message.response()}
          | {:error, :not_found}
          | {:error, :timeout}
          | {:error, :closed}
  def send_message(node, message, timeout \\ 0)

  def send_message(public_key, message, timeout) when is_binary(public_key) do
    case get_node_info(public_key) do
      {:ok, node} ->
        send_message(node, message, timeout)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def send_message(node, message, timeout) do
    timeout = if timeout == 0, do: Message.get_timeout(message), else: timeout
    do_send_message(node, message, timeout)
  end

  defdelegate do_send_message(node, message, timeout), to: Client, as: :send_message

  @doc """
  Return the nearest storages nodes from the local node
  """
  @spec sort_by_nearest_nodes(list(Node.t())) :: list(Node.t())
  def sort_by_nearest_nodes(storage_nodes) when is_list(storage_nodes) do
    case get_node_info(Crypto.first_node_public_key()) do
      {:ok, %Node{network_patch: network_patch}} ->
        sort_by_nearest_nodes(storage_nodes, network_patch)

      {:error, :not_found} ->
        storage_nodes
    end
  end

  @doc """
  Get the nearest nodes from a specified node and a list of nodes to compare with

  ## Examples

     iex> list_nodes = [
     ...>   %Node{network_patch: "AA0"},
     ...>   %Node{network_patch: "F50"},
     ...>   %Node{network_patch: "3A2"}
     ...> ]
     ...> 
     ...> P2P.sort_by_nearest_nodes(list_nodes, "12F")
     [
       %Node{network_patch: "3A2"},
       %Node{network_patch: "AA0"},
       %Node{network_patch: "F50"}
     ]

     iex> list_nodes = [
     ...>   %Node{network_patch: "AA0"},
     ...>   %Node{network_patch: "F50"},
     ...>   %Node{network_patch: "3A2"}
     ...> ]
     ...> 
     ...> P2P.sort_by_nearest_nodes(list_nodes, "C3A")
     [
       %Node{network_patch: "F50"},
       %Node{network_patch: "AA0"},
       %Node{network_patch: "3A2"}
     ]
  """
  @spec sort_by_nearest_nodes(node_list :: Enumerable.t(), network_patch :: binary()) ::
          Enumerable.t()
  def sort_by_nearest_nodes(storage_nodes, network_patch) when is_binary(network_patch) do
    Enum.sort_by(storage_nodes, &network_distance(&1.network_patch, network_patch))
  end

  @doc """
  Compute a network distance between two network patches
  """
  @spec network_distance(binary(), binary()) :: float()
  def network_distance(patch_a, patch_b) when is_binary(patch_a) and is_binary(patch_b) do
    [first_digit_a, second_digit_a, _] =
      patch_a |> String.split("", trim: true) |> Enum.map(&hex_val/1)

    [first_digit_b, second_digit_b, _] =
      patch_b |> String.split("", trim: true) |> Enum.map(&hex_val/1)

    :math.sqrt(
      abs(
        (first_digit_a - first_digit_b) * (first_digit_a - first_digit_b) +
          (second_digit_a - second_digit_b) * (second_digit_a - second_digit_b)
      )
    )
  end

  defp hex_val(val) do
    {int, _} = Integer.parse(val, 16)
    int
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
  Create a sequence of bits from a list of node and a subset
  by setting the bit where the subset node if found

  ## Examples

      iex> node_list = [
      ...>   %Node{first_public_key: "key1"},
      ...>   %Node{first_public_key: "key2"},
      ...>   %Node{first_public_key: "key3"}
      ...> ]
      ...> 
      ...> subset = [%Node{first_public_key: "key2"}]
      ...> P2P.bitstring_from_node_subsets(node_list, subset)
      <<0::1, 1::1, 0::1>>

      iex> node_list = [
      ...>   %Node{first_public_key: "key1"},
      ...>   %Node{first_public_key: "key2"},
      ...>   %Node{first_public_key: "key3"}
      ...> ]
      ...> 
      ...> subset = [%Node{first_public_key: "key2"}, %Node{first_public_key: "key3"}]
      ...> P2P.bitstring_from_node_subsets(node_list, subset)
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
  def load_transaction(tx = %Transaction{type: :node, previous_public_key: previous_public_key}) do
    :ok = MemTableLoader.load_transaction(tx)

    previous_public_key
    |> TransactionChain.get_first_public_key()
    |> get_node_info!()
    |> do_connect_node()
  end

  def load_transaction(tx), do: MemTableLoader.load_transaction(tx)

  @doc """
  Send multiple message at once for the given nodes.
  """
  @spec broadcast_message(list(Node.t()), Message.t()) :: :ok
  def broadcast_message(nodes, message) do
    Task.Supervisor.start_child(TaskSupervisor, fn -> do_broadcast_message(nodes, message) end)
    :ok
  end

  defp do_broadcast_message(nodes, message) do
    Task.Supervisor.async_stream_nolink(TaskSupervisor, nodes, &send_message(&1, message),
      ordered: false,
      on_timeout: :kill_task,
      timeout: Message.get_timeout(message) + 2000
    )
    |> Stream.run()
  end

  @doc """
  Check for possible duplicate nodes (IP spoofing).

  Returns true if matching node {ip,port} has a different first public key.

  ## Examples

    Returns false when the tuple {ip, port} is not found

      iex> P2P.duplicating_node?({127, 0, 0, 1}, 3000, "node_key0", [])
      false

      iex> P2P.duplicating_node?({127, 0, 0, 1}, 3000, "node_key0", [
      ...>   %Node{ip: {127, 0, 0, 1}, port: 3001}
      ...> ])
      false

    Returns false when the node with the ip/PORT is found but the chain of keys is followed

      iex> P2P.duplicating_node?({127, 0, 0, 1}, 3000, "node_key1", [
      ...>   %Node{ip: {127, 0, 0, 1}, port: 3000, last_address: Crypto.derive_address("node_key1")}
      ...> ])
      false

    Returns true when the node with the ip/PORT is found but the chain of keys doesn't match

      iex> P2P.duplicating_node?({127, 0, 0, 1}, 3000, "node_key10", [
      ...>   %Node{ip: {127, 0, 0, 1}, port: 3000, last_address: Crypto.derive_address("node_key1")}
      ...> ])
      true
  """
  @spec duplicating_node?(
          :inet.ip_address(),
          :inet.port_number(),
          Archethic.Crypto.key(),
          list(Node.t())
        ) ::
          boolean()
  def duplicating_node?(tx_ip, tx_port, prev_public_key, nodes \\ list_nodes()) do
    case Enum.find(nodes, &(&1.ip == tx_ip and &1.port == tx_port)) do
      nil ->
        false

      %Node{last_address: last_address} ->
        Crypto.derive_address(prev_public_key) != last_address
    end
  end

  @doc """
  Reorder a list of nodes to ensure the current node is only called at the end.
  This will enforce the remote nodes to be called first, ensuring a better distribution of the work.

  ## Examples

      iex> [
      ...>   %Node{first_public_key: "key1"},
      ...>   %Node{first_public_key: "key2"},
      ...>   %Node{first_public_key: "key3"},
      ...>   %Node{first_public_key: "key4"}
      ...> ]
      ...> |> P2P.unprioritize_node("key1")
      [
        %Node{first_public_key: "key2"},
        %Node{first_public_key: "key3"},
        %Node{first_public_key: "key4"},
        %Node{first_public_key: "key1"}
      ]
  """
  @spec unprioritize_node(list(Node.t()), Crypto.key()) :: list(Node.t())
  def unprioritize_node(node_list, discarded_node_public_key) do
    case Enum.find_index(node_list, &(&1.first_public_key == discarded_node_public_key)) do
      nil ->
        node_list

      index ->
        {node, list} = List.pop_at(node_list, index)
        :lists.flatten([list | [node]])
    end
  end

  @doc """
  Send a message to a list of nodes and perform a read quorum
  """
  @spec quorum_read(
          node_list :: list(Node.t()),
          message :: Message.t(),
          conflict_resolver :: (list(Message.t()) -> Message.t()),
          timeout :: non_neg_integer(),
          acceptance_resolver :: (Message.t() -> boolean()),
          consistency_level :: pos_integer()
        ) ::
          {:ok, Message.t()} | {:error, :network_issue} | {:error, :acceptance_failed}
  def quorum_read(
        nodes,
        message,
        conflict_resolver \\ fn results -> List.first(results) end,
        timeout \\ 0,
        acceptance_resolver \\ fn _ -> true end,
        consistency_level \\ 3
      )

  def quorum_read(
        nodes,
        message,
        conflict_resolver,
        timeout,
        acceptance_resolver,
        consistency_level
      ) do
    nodes
    |> Enum.filter(&node_connected?/1)
    |> sort_by_nearest_nodes()
    |> unprioritize_node(Crypto.first_node_public_key())
    |> Enum.chunk_every(consistency_level)
    |> Enum.reduce_while(nil, fn nodes, previous_result ->
      results =
        Task.Supervisor.async_stream_nolink(
          TaskSupervisor,
          nodes,
          &send_message(&1, message, timeout),
          ordered: false,
          on_timeout: :kill_task,
          timeout: timeout + 2000
        )
        |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
        |> Stream.map(fn {:ok, {:ok, res}} -> res end)
        |> Enum.to_list()

      if Enum.empty?(results) do
        {:cont, previous_result}
      else
        result =
          if previous_result == nil do
            reduce_results(results, conflict_resolver)
          else
            reduce_results([previous_result | results], conflict_resolver)
          end

        if acceptance_resolver.(result) do
          {:halt, result}
        else
          {:cont, result}
        end
      end
    end)
    |> then(fn
      nil ->
        {:error, :network_issue}

      result ->
        if acceptance_resolver.(result) do
          {:ok, result}
        else
          {:error, :acceptance_failed}
        end
    end)
  end

  defp reduce_results(results, conflict_resolver) do
    distinct_elems = Enum.dedup(results)

    # If the results are the same, then we reached consistency
    if length(distinct_elems) == 1 do
      List.first(distinct_elems)
    else
      # If the results differ, we can apply a conflict resolver to merge the result into
      # a consistent response
      conflict_resolver.(distinct_elems)
    end
  end

  @doc """
  Update the node's network patch
  """
  @spec update_node_network_patch(Crypto.key(), String.t()) :: :ok
  defdelegate update_node_network_patch(node_public_key, network_patch), to: MemTable
end
