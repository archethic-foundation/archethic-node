defmodule UnirisP2P.Node do
  @moduledoc """
  Describe an Uniris node and holding its own process to enable fast lookup and update.

  A geographical patch is computed from the IP based on a GeoIP lookup to get the coordinates.

  P2P view freshness are computed through a supervised connection to identify the availability and the
  average of availability of the node.

  Each node by default are not authorized, there become autorized and able to be a validator
  when a shared secret transaction involve it.
  """

  use GenServer

  alias UnirisP2P.NodeRegistry
  alias UnirisP2P.GeoPatch

  @enforce_keys [
    :first_public_key,
    :last_public_key,
    :ip,
    :port
  ]
  defstruct [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :network_patch,
    availability: 0,
    average_availability: 0,
    availability_history: <<>>,
    authorized?: false
  ]

  @type t() :: %__MODULE__{
          first_public_key: binary(),
          last_public_key: binary(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          geo_patch: binary(),
          network_patch: binary(),
          availability: boolean(),
          average_availability: float(),
          availability_history: bitstring(),
          authorized?: boolean()
        }

  @doc """
  Create a new process for the node and register it with its public keys and IP address

  ## Examples

     iex> {:ok, pid} = UnirisP2P.Node.start_link(first_public_key: "first_public_key", last_public_key: "last_public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> match?([{_, _}], Registry.lookup(UnirisP2P.NodeRegistry, "first_public_key"))
     true
     iex> match?([{_, _}], Registry.lookup(UnirisP2P.NodeRegistry, "last_public_key"))
     true
     iex> match?([{_, _}], Registry.lookup(UnirisP2P.NodeRegistry, {127, 0, 0, 1}))
     true
  """
  def start_link(
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        ip: ip,
        port: port
      ) do
    GenServer.start_link(__MODULE__, [first_public_key, last_public_key, ip, port],
      name: via_tuple(first_public_key)
    )
  end

  def start_link(node = %__MODULE__{first_public_key: first_public_key}) do
    GenServer.start_link(__MODULE__, [node], name: via_tuple(first_public_key))
  end

  def init([first_public_key, last_public_key, ip, port]) do
    Registry.register(NodeRegistry, last_public_key, [])
    Registry.register(NodeRegistry, ip, [])
    patch = GeoPatch.from_ip(ip)

    data = %__MODULE__{
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      ip: ip,
      port: port,
      geo_patch: patch,
      network_patch: patch,
      average_availability: 0,
      availability: 0
    }

    {:ok, data}
  end

  def init([node = %__MODULE__{ip: ip, last_public_key: last_public_key}]) do
    Registry.register(NodeRegistry, last_public_key, [])
    Registry.register(NodeRegistry, ip, [])
    {:ok, node}
  end

  def handle_cast(:available, state = %{availability_history: history}) do
    new_history =
      case history do
        <<>> ->
          <<1::1>>

        <<1::1, _::bitstring>> ->
          history

        <<0::1, _::bitstring>> ->
          <<1::1, history::bitstring>>
      end

    new_state =
      state
      |> Map.put(:availability_history, new_history)
      |> Map.put(:availability, 1)
      |> Map.put(:average_availability, new_average_availability(new_history))

    {:noreply, new_state}
  end

  def handle_cast(:unavailable, state = %{availability_history: history}) do
    new_history =
      case history do
        <<>> ->
          <<0::1>>

        <<0::1, _::bitstring>> ->
          history

        <<1::1, _::bitstring>> ->
          <<0::1, history::bitstring>>
      end

    new_state =
      state
      |> Map.put(:availability_history, new_history)
      |> Map.put(:availability, 0)
      |> Map.put(:average_availability, new_average_availability(new_history))

    {:noreply, new_state}
  end

  def handle_cast({:update_basics, last_public_key, ip, port}, state) do
    new_state =
      state
      |> Map.put(:last_public_key, last_public_key)
      |> Map.put(:ip, ip)
      |> Map.put(:port, port)

    {:noreply, new_state}
  end

  def handle_cast({:update_network_patch, network_patch}, state) do
    {:noreply, Map.put(state, :network_patch, network_patch)}
  end

  def handle_cast({:update_average_availability, avg_availability}, state) do
    new_state =
      state
      |> Map.put(:average_history, <<>>)
      |> Map.put(:average_availability, avg_availability)

    {:noreply, new_state}
  end

  def handle_cast(:authorize, state) do
    {:noreply, Map.put(state, :authorized?, true)}
  end

  def handle_call(:details, _from, state) do
    {:reply, state, state}
  end

  defp new_average_availability(history) do
    list = for <<view::1 <- history>>, do: view

    list
    |> Enum.frequencies()
    |> Map.get(1)
    |> case do
      nil ->
        0.0
      available_times ->
        available_times / bit_size(history)
    end


  end

  @doc """
  Mark the node as available

  ## Examples

     iex> UnirisP2P.Node.start_link(first_public_key: "public_key", last_public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> :ok = UnirisP2P.Node.available("public_key")
     iex> %UnirisP2P.Node{
     ...>   availability: availability,
     ...>   average_availability: average_availability,
     ...>   availability_history: history
     ...> } = UnirisP2P.Node.details("public_key")
     iex> [availability, average_availability, history]
     [1, 1.0, <<1::1>>]
  """
  @spec available(UnirisCrypto.key() | :inet.ip_address()) :: :ok
  def available(node_public_key) when is_binary(node_public_key) do
    GenServer.cast(via_tuple(node_public_key), :available)
  end

  def available({_, _, _, _} = ip) do
    GenServer.cast(via_tuple(ip), :available)
  end

  @doc """
  Mark the node as unavailable

  ## Examples

      iex> UnirisP2P.Node.start_link(first_public_key: "public_key", last_public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
      iex> :ok = UnirisP2P.Node.available("public_key")
      iex> :ok = UnirisP2P.Node.unavailable("public_key")
      iex> %UnirisP2P.Node{
      ...>   availability: availability,
      ...>   average_availability: average_availability,
      ...>   availability_history: history
      ...> } = UnirisP2P.Node.details("public_key")
      iex> [availability, average_availability, history]
      [0, 0.5, <<0::1, 1::1>>]
  """
  @spec unavailable(UnirisCrypto.key() | :inet.ip_address()) :: :ok
  def unavailable(node_public_key) when is_binary(node_public_key) do
    GenServer.cast(via_tuple(node_public_key), :unavailable)
  end

  def unavailable({_, _, _, _} = ip) do
    GenServer.cast(via_tuple(ip), :unavailable)
  end

  @doc """
  Get the details of a node

  ## Examples

     iex> UnirisP2P.Node.start_link(first_public_key: "first_public_key", last_public_key: "last_public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> %UnirisP2P.Node{ip: ip, port: port} = UnirisP2P.Node.details("first_public_key")
     iex> {ip, port}
     {{127, 0, 0, 1}, 3000}

     iex> UnirisP2P.Node.start_link(first_public_key: "first_public_key", last_public_key: "last_public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> %UnirisP2P.Node{ip: ip, port: port} = UnirisP2P.Node.details("last_public_key")
     iex> {ip, port}
     {{127, 0, 0, 1}, 3000}

     iex> UnirisP2P.Node.start_link(first_public_key: "first_public_key", last_public_key: "last_public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> %UnirisP2P.Node{last_public_key: public_key} = UnirisP2P.Node.details({127, 0, 0, 1})
     iex> public_key
     "last_public_key"

  """
  @spec details(node_public_key :: UnirisCrypto.key()) :: __MODULE__.t()
  def details(node_public_key) when is_binary(node_public_key) do
    GenServer.call(via_tuple(node_public_key), :details)
  end

  @spec details(node_process :: pid()) :: __MODULE__.t()
  def details(pid) when is_pid(pid) do
    GenServer.call(pid, :details)
  end

  def details(ip = {_, _, _, _}) do
    GenServer.call(via_tuple(ip), :details)
  end

  @doc """
  Update the basic information of the node including: last public key, ip, port.

  A geo IP lookup will be perform to change the GeoPatch
  """
  @spec update_basics(
          node_first_public_key :: UnirisCrypto.key(),
          node_last_public_key :: UnirisCrypto.key(),
          node_ip :: :inet.ip_address(),
          node_port :: :inet.port_number()
        ) :: :ok
  def update_basics(first_public_key, last_public_key, ip, port) do
    GenServer.cast(via_tuple(first_public_key), {:update_basics, last_public_key, ip, port})
  end

  @doc """
  Update the network patch for a given node

  ## Examples

     iex> {:ok, pid} = UnirisP2P.Node.start_link(first_public_key: "public_key", last_public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> :ok = UnirisP2P.Node.update_network_patch("public_key", "AA0")
     iex> %UnirisP2P.Node{network_patch: network_patch} = UnirisP2P.Node.details("public_key")
     iex> network_patch
     "AA0"

  """
  @spec update_network_patch(node_public_key :: UnirisCrypto.key(), geo_patch :: binary()) :: :ok
  def update_network_patch(public_key, network_patch) do
    [{pid, _}] = Registry.lookup(NodeRegistry, public_key)
    GenServer.cast(pid, {:update_network_patch, network_patch})
  end

  @doc """
  Update the average availability of the node and reset the history

  ## Examples

     iex> {:ok, pid} = UnirisP2P.Node.start_link(first_public_key: "public_key", last_public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> :ok = UnirisP2P.Node.update_average_availability("public_key", 0.5)
     iex> %UnirisP2P.Node{average_availability: avg_availability, availability_history: history} = UnirisP2P.Node.details("public_key")
     iex> [avg_availability, history]
     [0.5, <<>>]
  """
  @spec update_average_availability(
          node_public_key :: UnirisCrypto.key(),
          average_availability :: float()
        ) :: :ok
  def update_average_availability(public_key, avg_availability)
      when is_float(avg_availability) and avg_availability >= 0 and
             avg_availability <= 1 do
    GenServer.cast(via_tuple(public_key), {:update_average_availability, avg_availability})
  end

  @doc """
  Mark the node as validator.

  ## Examples

     iex> UnirisP2P.Node.start_link(first_public_key: "public_key", last_public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
     iex> UnirisP2P.Node.authorize("public_key")
     iex> %UnirisP2P.Node{authorized?: is_authorized} = UnirisP2P.Node.details("public_key")
     iex> is_authorized
     true
  """
  @spec authorize(UnirisCrypto.key() | __MODULE__.t()) :: :ok
  def authorize(public_key) when is_binary(public_key) do
    GenServer.cast(via_tuple(public_key), :authorize)
  end

  def authorize(%__MODULE__{first_public_key: public_key}) do
    GenServer.cast(via_tuple(public_key), :authorize)
  end

  @spec via_tuple(id :: UnirisCrypto.key() | :inet.ip_address()) :: tuple()
  defp via_tuple(id) do
    {:via, Registry, {NodeRegistry, id}}
  end
end
