defmodule Uniris.Storage.Memory.NetworkLedger do
  @moduledoc false

  @transaction_table :network_transactions
  @origin_key_table :origin_keys
  @origin_key_by_type_table :origin_key_by_type
  @proposal_table :proposals
  @node_genesis_table :node_genesis
  @node_by_last_key_table :node_last_key
  @node_table :nodes
  @counter_table :network_tx_counter
  @authorized_nodes_table :authorized_nodes
  @ready_nodes_table :ready_nodes

  alias Uniris.Crypto

  alias Uniris.P2P.GeoPatch
  alias Uniris.P2P.Node

  alias Uniris.PubSub

  alias Uniris.Storage.Backend, as: DB

  alias Uniris.Transaction
  alias Uniris.TransactionData

  use GenServer

  require Logger

  @type origin_family :: :software | :usb | :biometric

  @spec list_origin_families() :: list(origin_family())
  def list_origin_families, do: [:software, :usb, :biometric]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Network Ledger...")
    init_tables()

    DB.list_transactions_by_type(:node, [
      :address,
      :type,
      :timestamp,
      :previous_public_key,
      data: [:content]
    ])
    |> Stream.concat(DB.list_transactions_by_type(:node_shared_secrets, [:address, :type]))
    |> Stream.concat(DB.list_transactions_by_type(:origin_shared_secrets, [:address, :type]))
    |> Stream.concat(DB.list_transactions_by_type(:code_proposal, [:address, :type]))
    |> Enum.sort_by(& &1.timestamp, DateTime)
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  defp init_tables do
    :ets.new(@transaction_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@origin_key_by_type_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@origin_key_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@proposal_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@node_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@node_genesis_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@node_by_last_key_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@counter_table, [:set, :named_table, :public])
    :ets.new(@ready_nodes_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@authorized_nodes_table, [:set, :named_table, :public, read_concurrency: true])
  end

  @doc """
  Load a transaction in the NetworkLedger memory database
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        type: :node,
        address: address,
        previous_public_key: previous_public_key,
        data: %TransactionData{
          content: content
        },
        timestamp: timestamp
      }) do
    :ok = add_node_transaction_address(address)
    :ok = index_node_public_key(address, previous_public_key)
    first_public_key = get_node_first_public_key_from_previous_key(previous_public_key)
    {ip, port} = extract_node_endpoint_from_content(content)

    :ets.update_counter(
      @counter_table,
      {:node, first_public_key},
      {2, 1},
      {{:node, first_public_key}, 0}
    )

    first_public_key
    |> get_node_info()
    |> case do
      {:error, :not_found} ->
        %Node{
          first_public_key: previous_public_key,
          last_public_key: previous_public_key,
          ip: ip,
          port: port,
          geo_patch: GeoPatch.from_ip(ip),
          network_patch: GeoPatch.from_ip(ip),
          enrollment_date: timestamp
        }

      {:ok, node} ->
        %{node | ip: ip, port: port, last_public_key: previous_public_key}
    end
    |> add_node_info
  end

  def load_transaction(%Transaction{type: :node_shared_secrets, address: address}) do
    :ets.update_counter(@counter_table, :node_shared_secrets, {2, 1}, {:node_shared_secrets, 0})
    add_node_shared_secret_address(address)
  end

  def load_transaction(%Transaction{
        type: :origin_shared_secrets,
        address: address,
        data: %TransactionData{content: content}
      }) do
    add_origin_shared_secret_address(address)

    content
    |> extract_origin_public_keys_from_content()
    |> Enum.each(fn {family, key} ->
      add_origin_public_key(family, key)
    end)
  end

  def load_transaction(%Transaction{type: :code_proposal, address: address}) do
    add_proposal_address(address)
  end

  defp extract_node_endpoint_from_content(content) do
    [ip_match, port_match] = Regex.scan(~r/(?<=ip:|port:).*/m, content)

    {:ok, ip} =
      ip_match
      |> List.first()
      |> String.trim()
      |> String.to_charlist()
      |> :inet.parse_address()

    port =
      port_match
      |> List.first()
      |> String.trim()
      |> String.to_integer()

    {ip, port}
  end

  defp extract_origin_public_keys_from_content(content) do
    Regex.scan(~r/(?<=origin_public_keys:).*/, content)
    |> Enum.flat_map(& &1)
    |> List.first()
    |> case do
      nil ->
        []

      str ->
        str
        |> String.trim()
        |> String.replace("[", "")
        |> String.replace("]", "")
        |> origin_public_keys_string_to_keyword
    end
  end

  defp origin_public_keys_string_to_keyword(origin_keys_string) do
    software_keys =
      extract_origin_public_keys_from_family(
        ~r/(?<=software: ).([A-Z0-9\, ])*/,
        origin_keys_string
      )

    usb_keys =
      extract_origin_public_keys_from_family(~r/(?<=usb: ).([A-Z0-9\, ])*/, origin_keys_string)

    biometric_keys =
      extract_origin_public_keys_from_family(
        ~r/(?<=biometric: ).([A-Z0-9\, ])*/,
        origin_keys_string
      )

    [
      software: software_keys,
      usb: usb_keys,
      biometric: biometric_keys
    ]
  end

  defp extract_origin_public_keys_from_family(family_regex, origin_keys_string) do
    Regex.scan(family_regex, origin_keys_string)
    |> Enum.flat_map(& &1)
    |> List.first()
    |> case do
      nil ->
        []

      str ->
        str
        |> String.trim()
        |> String.split(",")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn key ->
          key
          |> String.trim()
          |> Base.decode16!()
        end)
    end
  end

  @doc """
  Retrieve the node P2P info by its public key
  """
  @spec get_node_info(Crypto.key()) :: {:ok, Node.t()} | {:error, :not_found}
  def get_node_info(key) when is_binary(key) do
    case :ets.lookup(@node_table, key) do
      [] ->
        case :ets.lookup(@node_by_last_key_table, key) do
          [{_, first_public_key}] ->
            [res] = :ets.lookup(@node_table, first_public_key)
            {:ok, tuple_to_node(res)}

          [] ->
            {:error, :not_found}
        end

      [res] ->
        {:ok, tuple_to_node(res)}
    end
  end

  @doc """
  List the P2P nodes
  """
  @spec list_nodes() :: list(Node.t())
  def list_nodes do
    @node_table
    |> :ets.select([{:"$1", [], [:"$1"]}])
    |> Enum.map(&tuple_to_node/1)
  end

  @doc """
  Add node info from a P2P Node
  """
  @spec add_node_info(Node.t()) :: :ok
  def add_node_info(node = %Node{}) do
    PubSub.notify_node_update(node)
    do_add_node_info(node)
  end

  defp do_add_node_info(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         ip: ip,
         port: port,
         geo_patch: geo_patch,
         network_patch: network_patch,
         available?: available?,
         authorized?: authorized?,
         availability_history: availability_history,
         average_availability: average_availability,
         authorization_date: authorization_date,
         ready?: ready?,
         ready_date: ready_date,
         enrollment_date: enrollment_date
       }) do
    true =
      :ets.insert(
        @node_table,
        {first_public_key, last_public_key, ip, port, geo_patch, network_patch, available?,
         availability_history, average_availability, authorized?, authorization_date, ready?,
         ready_date, enrollment_date}
      )

    true = :ets.insert(@node_by_last_key_table, {last_public_key, first_public_key})

    if authorized? do
      true = :ets.insert(@authorized_nodes_table, {last_public_key})
    end

    if ready? do
      true = :ets.insert(@ready_nodes_table, {last_public_key})
    end

    :ok
  end

  @doc """
  Mark the node as validator.
  """
  @spec authorize_node(binary(), DateTime.t()) :: :ok
  def authorize_node(public_key, date = %DateTime{}) when is_binary(public_key) do
    true = :ets.update_element(@node_table, public_key, [{10, true}, {11, date}])
    true = :ets.insert(@authorized_nodes_table, {public_key})
    :ok
  end

  @doc """
  Return the list of authorized nodes. An indexed lookup table is used to avoid full scan
  """
  @spec list_authorized_nodes() :: list(Node.t())
  def list_authorized_nodes do
    :ets.foldl(
      fn {public_key}, acc ->
        [res] = :ets.lookup(@node_table, public_key)
        [tuple_to_node(res) | acc]
      end,
      [],
      @authorized_nodes_table
    )
  end

  @doc """
  Reset the authorized nodes
  """
  @spec reset_authorized_nodes() :: :ok
  def reset_authorized_nodes do
    :ets.tab2list(@authorized_nodes_table)
    |> Enum.each(fn {public_key} ->
      true = :ets.delete(@authorized_nodes_table, public_key)
      true = :ets.update_element(@node_table, public_key, [{10, false}, {11, nil}])
    end)

    :ok
  end

  @doc """
  Update the average availability of the node and reset the history
  """
  @spec update_node_average_availability(binary(), float()) :: :ok
  def update_node_average_availability(public_key, avg_availability)
      when is_binary(public_key) and is_float(avg_availability) do
    true = :ets.update_element(@node_table, public_key, [{8, <<>>}, {9, avg_availability}])
    :ok
  end

  @doc """
  Update the average availability of the node and reset the history
  """
  @spec update_node_network_patch(binary(), binary()) :: :ok
  def update_node_network_patch(public_key, patch)
      when is_binary(public_key) and is_binary(patch) do
    true = :ets.update_element(@node_table, public_key, [{6, patch}])
    :ok
  end

  @doc """
  Mark the node as ready meaning the end of bootstraping and readyness
  to store transaction
  """
  @spec set_node_ready(binary(), DateTime.t()) :: :ok
  def set_node_ready(public_key, date = %DateTime{}) when is_binary(public_key) do
    true = :ets.update_element(@node_table, public_key, [{12, true}, {13, date}])
    true = :ets.insert(@ready_nodes_table, {public_key})
    :ok
  end

  @doc """
  Return the list of ready nodes. An indexed lookup table is used to avoid full scan
  """
  @spec list_ready_nodes() :: list(Node.t())
  def list_ready_nodes do
    :ets.foldl(
      fn {public_key}, acc ->
        [res] = :ets.lookup(@node_table, public_key)
        [tuple_to_node(res) | acc]
      end,
      [],
      @ready_nodes_table
    )
  end

  @spec set_node_enrollment_date(binary(), DateTime.t()) :: :ok
  def set_node_enrollment_date(public_key, date = %DateTime{}) when is_binary(public_key) do
    true = :ets.update_element(@node_table, public_key, [{14, date}])
    :ok
  end

  @doc """
  Mark the node as available
  """
  @spec set_node_available(binary()) :: :ok
  def set_node_available(public_key) when is_binary(public_key) do
    true = :ets.update_element(@node_table, public_key, [{7, true}])
    :ok
  end

  @doc """
  Mark the node as unavailable
  """
  @spec set_node_unavailable(binary()) :: :ok
  def set_node_unavailable(public_key) when is_binary(public_key) do
    true = :ets.update_element(@node_table, public_key, [{7, false}])
    :ok
  end

  @doc """
  Set the node as available if previously flagged as offline
  """
  @spec increase_node_availability(binary()) :: :ok
  def increase_node_availability(public_key) when is_binary(public_key) do
    case :ets.lookup_element(@node_table, public_key, 8) do
      <<1::1, _::bitstring>> ->
        :ok

      <<0::1, _::bitstring>> = history ->
        new_history = <<1::1, history::bitstring>>
        true = :ets.update_element(@node_table, public_key, {8, new_history})
        :ok
    end
  end

  @doc """
  Set the node as unavailable if previously flagged as online
  """
  @spec decrease_node_availability(binary()) :: :ok
  def decrease_node_availability(public_key) when is_binary(public_key) do
    case :ets.lookup_element(@node_table, public_key, 8) do
      <<0::1, _::bitstring>> ->
        :ok

      <<1::1, _::bitstring>> = history ->
        new_history = <<0::1, history::bitstring>>
        true = :ets.update_element(@node_table, public_key, {8, new_history})
        :ok
    end
  end

  @doc """
  Search the first node public key from the last previous public key.

  A reverse lookup is performed to find a previous transaction using this previous public key.
  """
  @spec get_node_first_public_key_from_previous_key(Crypto.key()) :: Crypto.key()
  def get_node_first_public_key_from_previous_key(previous_public_key)
      when is_binary(previous_public_key) do
    case :ets.lookup(@node_genesis_table, Crypto.hash(previous_public_key)) do
      [] ->
        previous_public_key

      [{_, first_public_key}] ->
        first_public_key
    end
  end

  # Register a new node transaction address.
  defp add_node_transaction_address(address) when is_binary(address) do
    add_transaction_by_type(:node, address)
  end

  # Index the node public key with the transaction address.
  # The previous public key is used to determine the genesis address and to determine to
  # register it as origin public key (if genesis)
  defp index_node_public_key(address, previous_public_key) do
    case :ets.lookup(@node_genesis_table, Crypto.hash(previous_public_key)) do
      [] ->
        true = :ets.insert(@node_genesis_table, {address, previous_public_key})

      [{_, first_public_key}] ->
        true = :ets.insert(@node_genesis_table, {address, first_public_key})
    end

    # TODO: detect which family to use (ie. software, hardware)
    case :ets.lookup(@origin_key_table, previous_public_key) do
      [] ->
        add_origin_public_key(:software, previous_public_key)

      _ ->
        :ok
    end
  end

  @doc """
  Retrieve the latest node transaction addresses
  """
  @spec list_node_transactions() :: list(binary())
  def list_node_transactions do
    list_transaction_by_type(:node)
  end

  @doc """
  Return the number of times the node changed
  """
  @spec count_node_changes(binary()) :: non_neg_integer()
  def count_node_changes(first_public_key) when is_binary(first_public_key) do
    case :ets.lookup(@counter_table, {:node, first_public_key}) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  @doc """
  Return the number of node shared secrets renewals
  """
  @spec count_node_shared_secrets() :: non_neg_integer()
  def count_node_shared_secrets do
    case :ets.lookup(@counter_table, :node_shared_secrets) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  # Register a new node shared secret transaction address
  @spec add_node_shared_secret_address(binary()) :: :ok
  defp add_node_shared_secret_address(address) when is_binary(address) do
    :ok = add_transaction_by_type(:node_shared_secrets, address)
    true = :ets.insert(@transaction_table, {:last_node_shared_secrets, address})
    :ok
  end

  # Register a new origin shared secret transaction address
  @spec add_origin_shared_secret_address(binary()) :: :ok
  defp add_origin_shared_secret_address(address) when is_binary(address) do
    add_transaction_by_type(:origin_shared_secrets, address)
  end

  @doc """
  Retrieve the last node shared secret transaction address
  """
  @spec get_last_node_shared_secrets_address() :: {:ok, binary()} | {:error, :not_found}
  def get_last_node_shared_secrets_address do
    case :ets.lookup(@transaction_table, :last_node_shared_secrets) do
      [{_, address}] ->
        {:ok, address}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Add a new origin public key by giving its family: biometric, software, usb

  Family can be used in the smart contract to provide a level of security
  """
  @spec add_origin_public_key(
          family :: SharedSecrets.origin_family(),
          key :: Crypto.key()
        ) :: :ok
  def add_origin_public_key(family, key) do
    true = :ets.insert(@origin_key_table, {key, family})
    true = :ets.insert(@origin_key_by_type_table, {family, key})
    :ok
  end

  @doc """
  Retrieve the origin public keys for a given family
  """
  @spec list_origin_public_keys(SharedSecrets.origin_family()) :: list(Uniris.Crypto.key())
  def list_origin_public_keys(family) do
    @origin_key_by_type_table
    |> :ets.lookup(family)
    |> Enum.map(fn {_, address} -> address end)
  end

  @doc """
  Retrieve all origin public keys across the families
  """
  @spec list_origin_public_keys() :: list(UnirisCrypto.key())
  def list_origin_public_keys do
    select = [{{:"$1", :_}, [], [:"$1"]}]
    :ets.select(@origin_key_table, select)
  end

  @doc """
  Register a code proposal transaction address
  """
  @spec add_proposal_address(binary()) :: :ok
  def add_proposal_address(address) do
    add_transaction_by_type(:code_proposal, address)
    :ets.insert(@proposal_table, {address, []})
    :ok
  end

  @doc """
  List all the code proposal transaction addresses
  """
  @spec list_code_proposals_addresses() :: list(binary())
  def list_code_proposals_addresses do
    list_transaction_by_type(:code_proposal)
  end

  defp add_transaction_by_type(type, address) do
    true = :ets.insert(@transaction_table, {type, address})
    :ok
  end

  defp list_transaction_by_type(type) do
    Enum.map(:ets.lookup(@transaction_table, type), fn {_, address} -> address end)
  end

  defp tuple_to_node(
         {first_public_key, last_public_key, ip, port, geo_patch, network_patch, available?,
          availability_history, average_availability, authorized?, authorization_date, ready?,
          ready_date, enrollment_date}
       ) do
    %Node{
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      ip: ip,
      port: port,
      geo_patch: geo_patch,
      network_patch: network_patch,
      available?: available?,
      availability_history: availability_history,
      average_availability: average_availability,
      authorized?: authorized?,
      authorization_date: authorization_date,
      ready?: ready?,
      ready_date: ready_date,
      enrollment_date: enrollment_date
    }
  end
end
