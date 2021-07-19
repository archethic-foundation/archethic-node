defmodule ArchEthic.P2P do
  @moduledoc """
  Handle P2P node discovery and messaging
  """
  alias ArchEthic.Crypto

  alias __MODULE__.BootstrappingSeeds
  alias __MODULE__.Client
  alias __MODULE__.GeoPatch
  alias __MODULE__.MemTable
  alias __MODULE__.MemTableLoader
  alias __MODULE__.Message
  alias __MODULE__.Node

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils

  require Logger

  @doc """
  Compute a geographical patch (zone) from an IP
  """
  @spec get_geo_patch(:inet.ip_address()) :: binary()
  defdelegate get_geo_patch(ip), to: GeoPatch, as: :from_ip

  @doc """
  Register a node and establish a connection with
  """
  @spec add_and_connect_node(Node.t()) :: :ok
  def add_and_connect_node(node = %Node{}) do
    :ok = MemTable.add_node(node)
    do_connect_node(node)
  end

  defp do_connect_node(%Node{
         ip: ip,
         port: port,
         transport: transport,
         first_public_key: first_public_key
       }) do
    if first_public_key == Crypto.first_node_public_key() do
      :ok
    else
      Client.new_connection(ip, port, transport, first_public_key)
      :ok
    end
  end

  @doc """
  List the nodes registered.
  """
  @spec list_nodes() :: list(Node.t())
  defdelegate list_nodes, to: MemTable

  @doc """
  Return the list of available nodes
  """
  @spec available_nodes() :: list(Node.t())
  defdelegate available_nodes, to: MemTable

  @doc """
  Add a node first public key to the list of nodes globally available.
  """
  @spec set_node_globally_available(first_public_key :: Crypto.key()) :: :ok
  defdelegate set_node_globally_available(first_public_key), to: MemTable, as: :set_node_available

  @doc """
  Remove a node first public key to the list of nodes globally available.
  """
  @spec set_node_globally_unavailable(first_public_key :: Crypto.key()) :: :ok
  defdelegate set_node_globally_unavailable(first_public_key),
    to: MemTable,
    as: :set_node_unavailable

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
  Determine if the node public key is authorized
  """
  @spec authorized_node?(Crypto.key()) :: boolean()
  def authorized_node?(node_public_key \\ Crypto.first_node_public_key())
      when is_binary(node_public_key) do
    Utils.key_in_node_list?(authorized_nodes(DateTime.utc_now()), node_public_key)
  end

  @doc """
  List the authorized nodes for the given datetime (default to now)
  """
  @spec authorized_nodes(DateTime.t()) :: list(Node.t())
  def authorized_nodes(date = %DateTime{} \\ DateTime.utc_now()) do
    Enum.filter(
      MemTable.authorized_nodes(),
      &(DateTime.diff(&1.authorization_date, DateTime.truncate(date, :second)) <= 0)
    )
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
  Send a P2P message to a node.

  If the exchange fails, the node availability history will decrease
  and will be locally unavailable until the next exchange
  """
  @spec send_message!(Crypto.key() | Node.t(), Message.request()) :: Message.response()
  def send_message!(node, message)

  def send_message!(public_key, message) when is_binary(public_key) do
    public_key
    |> get_node_info!
    |> send_message!(message)
  end

  def send_message!(node = %Node{ip: ip, port: port}, message) do
    case Client.send_message(node, message) do
      {:ok, data} ->
        data

      {:error, :network_issue} ->
        raise "Messaging error with #{:inet.ntoa(ip)}:#{port}"
    end
  end

  @spec send_message(Crypto.key() | Node.t(), Message.t()) ::
          {:ok, Message.t()}
          | {:error, :not_found}
          | {:error, :network_issue}
  def send_message(node, message)

  def send_message(public_key, message) when is_binary(public_key) do
    with {:ok, node} <- get_node_info(public_key),
         {:ok, data} <- send_message(node, message) do
      {:ok, data}
    end
  end

  def send_message(node = %Node{first_public_key: first_public_key}, message) do
    start = System.monotonic_time()

    case Client.send_message(node, message) do
      {:ok, data} ->
        :telemetry.execute(
          [:archethic, :p2p, :send_message],
          %{duration: System.monotonic_time() - start},
          %{message: message.__struct__ |> Module.split() |> List.last() |> Macro.underscore()}
        )

        MemTable.increase_node_availability(first_public_key)
        {:ok, data}

      {:error, :network_issue} ->
        MemTable.decrease_node_availability(first_public_key)
        {:error, :network_issue}
    end
  end

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
       %Node{network_patch: "F50"},
       %Node{network_patch: "AA0"},
       %Node{network_patch: "3A2"}
     ]
  """
  @spec nearest_nodes(node_list :: Enumerable.t(), network_patch :: binary()) :: Enumerable.t()
  def nearest_nodes(storage_nodes, network_patch) when is_binary(network_patch) do
    Enum.sort_by(storage_nodes, &distance(&1.network_patch, network_patch))
  end

  defp distance(patch_a, patch_b) when is_binary(patch_a) and is_binary(patch_b) do
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
  @spec broadcast_message(list(Node.t()), Message.request()) :: :ok
  def broadcast_message(nodes, message) do
    nodes
    |> Task.async_stream(&send_message(&1, message), ordered: false, on_timeout: :kill_task)
    |> Stream.run()
  end

  @doc """
  Send a message to a list of nodes trying to get response from the closest node.

  If the node does not respond, a new node will be picked
  """
  @spec reply_first(
          node_list :: list(Node.t()),
          message :: Message.request(),
          opts :: [node_ack?: boolean(), patch: binary()]
        ) ::
          {:ok, Message.response()}
          | {:ok, Message.response(), Node.t()}
          | {:error, :network_issue}
  def reply_first(nodes, message, opts \\ [])
      when is_list(nodes) and is_struct(message) and is_list(opts) do
    node_ack? = Keyword.get(opts, :node_ack?, false)
    patch = Keyword.get(opts, :patch)

    with nil <- patch,
         {:error, :not_found} <- get_node_info(Crypto.first_node_public_key()) do
      get_first_reply(nodes, message, node_ack?)
    else
      {:ok, %Node{network_patch: patch}} ->
        nodes
        |> nearest_nodes(patch)
        |> get_first_reply(message, node_ack?)

      patch ->
        nodes
        |> nearest_nodes(patch)
        |> get_first_reply(message, node_ack?)
    end
  end

  defp get_first_reply([], _, _), do: {:error, :network_issue}

  defp get_first_reply(nodes, message, node_ack?) do
    nodes
    |> Enum.filter(&Node.locally_available?/1)
    |> do_get_first_reply(message, node_ack?)
  end

  defp do_get_first_reply(
         [node = %Node{first_public_key: first_public_key} | rest],
         message,
         node_ack?
       ) do
    case send_message(node, message) do
      {:error, :network_issue} ->
        MemTable.decrease_node_availability(first_public_key)
        get_first_reply(rest, message, node_ack?)

      {:ok, data} ->
        MemTable.increase_node_availability(first_public_key)
        (node_ack? && {:ok, data, node}) || {:ok, data}
    end
  end

  @doc """
  Request data atomically from a list nodes chunked by batch.

  If the first batch responses are not atomic, the next one will be used until the end of the list.
  """
  @spec reply_atomic(
          node_list :: list(Node.t()),
          batch_size :: non_neg_integer(),
          request :: Message.request(),
          options :: [patch: binary(), compare_fun: (any() -> any())]
        ) ::
          {:ok, Message.response()} | {:error, :network_issue}
  def reply_atomic(nodes, batch_size, message, opts \\ [])
      when is_list(nodes) and is_integer(batch_size) and batch_size > 0 do
    patch = Keyword.get(opts, :patch)
    compare_fun = Keyword.get(opts, :compare_fun, fn x -> x end)

    with nil <- patch,
         {:error, :not_found} <- get_node_info(Crypto.first_node_public_key()) do
      nodes
    else
      {:ok, %Node{network_patch: patch}} ->
        nearest_nodes(nodes, patch)

      patch ->
        nearest_nodes(nodes, patch)
    end
    |> Enum.filter(&Node.locally_available?/1)
    |> Enum.chunk_every(batch_size)
    |> do_reply_atomic(message, compare_fun)
  end

  defp do_reply_atomic([], _, _), do: {:error, :network_issue}

  defp do_reply_atomic([nodes | rest], message, compare_fun) do
    responses =
      nodes
      |> Task.async_stream(
        fn node = %Node{first_public_key: first_public_key} ->
          case send_message(node, message) do
            {:error, :network_issue} ->
              MemTable.decrease_node_availability(first_public_key)
              {:error, :network_issue}

            {:ok, res} ->
              MemTable.increase_node_availability(first_public_key)
              res
          end
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(&elem(&1, 1))
      |> Stream.reject(&match?({:error, :network_issue}, &1))
      |> Enum.dedup_by(compare_fun)

    case responses do
      [res] ->
        {:ok, res}

      _ ->
        do_reply_atomic(rest, message, compare_fun)
    end
  end
end
