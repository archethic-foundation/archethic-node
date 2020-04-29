defmodule UnirisCore.P2P.Node do
  @moduledoc """
  Describe an Uniris node and holding its own process to enable fast lookup and update.

  A geographical patch is computed from the IP based on a GeoIP lookup to get the coordinates.

  P2P view freshness are computed through a supervised connection to identify the availability and the
  average of availability of the node.

  Each node by default are not authorized and become come when a node shared secrets transaction involve it.
  Each node by default is not ready, and become it when a beacon pool receive a readyness message after the node bootstraping
  """

  use GenServer

  require Logger

  alias UnirisCore.P2P.NodeRegistry
  alias UnirisCore.P2P.GeoPatch
  alias UnirisCore.P2P.NodeClient

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
    authorized?: false,
    ready?: false,
    client_pid: nil,
    enrollment_date: nil
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
          authorized?: boolean(),
          ready?: boolean(),
          client_pid: pid(),
          enrollment_date: DateTime.t()
        }

  @doc """
  Create a new process for the node registered it with its public keys and IP address
  A new process is spawwned and linked to establish the connection with the node.
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start_link(node = %__MODULE__{}) do
    GenServer.start_link(__MODULE__, node)
  end

  def init(opts \\ [])

  def init(
        node = %__MODULE__{
          ip: ip,
          port: port,
          first_public_key: first_public_key,
          last_public_key: last_public_key,
          geo_patch: geo_patch
        }
      ) do
    Registry.register(NodeRegistry, last_public_key, [])
    Registry.register(NodeRegistry, ip, [])
    Registry.register(NodeRegistry, first_public_key, [])

    {:ok, pid} = NodeClient.start_link(ip: ip, port: port, parent_pid: self())
    Process.monitor(pid)

    if geo_patch == nil do
      patch = GeoPatch.from_ip(ip)
      {:ok, %{node | client_pid: pid, geo_patch: patch, network_patch: patch}}
    else
      {:ok, %{node | client_pid: pid}}
    end
  end

  def init(opts) do
    first_public_key = Keyword.get(opts, :first_public_key)
    last_public_key = Keyword.get(opts, :last_public_key)
    ip = Keyword.get(opts, :ip)
    port = Keyword.get(opts, :port)

    Registry.register(NodeRegistry, first_public_key, [])
    Registry.register(NodeRegistry, last_public_key, [])
    Registry.register(NodeRegistry, ip, [])
    patch = GeoPatch.from_ip(ip)

    node = %__MODULE__{
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      ip: ip,
      port: port,
      geo_patch: patch,
      network_patch: patch
    }

    {:ok, pid} = NodeClient.start_link(ip: ip, port: port, parent_pid: self())
    Process.monitor(pid)

    {:ok, %{node | client_pid: pid}}
  end

  def handle_call(
        {:update_basics, last_public_key, ip, port},
        _from,
        state = %{first_public_key: first_public_key, last_public_key: previous_public_key}
      ) do
    new_state =
      state
      |> Map.put(:last_public_key, last_public_key)
      |> Map.put(:ip, ip)
      |> Map.put(:port, port)
      |> Map.put(:geo_patch, GeoPatch.from_ip(ip))

    unless previous_public_key == first_public_key do
      Registry.unregister(NodeRegistry, previous_public_key)
    end

    Registry.register(NodeRegistry, last_public_key, [])

    {:reply, :ok, new_state}
  end

  def handle_call({:update_network_patch, network_patch}, _from, state) do
    {:reply, :ok, Map.put(state, :network_patch, network_patch)}
  end

  def handle_call({:update_average_availability, avg_availability}, _from, state) do
    new_state =
      state
      |> Map.put(:availability_history, <<>>)
      |> Map.put(:average_availability, avg_availability)

    {:reply, :ok, new_state}
  end

  def handle_call(:authorize, _from, state = %{authorized?: false}) do
    Logger.debug("Node #{Base.encode16(state.first_public_key)} is authorized")
    {:reply, :ok, Map.put(state, :authorized?, true)}
  end

  def handle_call(:authorize, _from, state), do: {:reply, :ok, state}

  def handle_call(:is_ready, _from, state = %{ready?: false}) do
    Logger.debug("Node #{Base.encode16(state.first_public_key)} is ready")
    {:reply, :ok, Map.put(state, :ready?, true)}
  end

  def handle_call(:is_ready, _from, state), do: {:reply, :ok, state}

  def handle_call({:set_enrollment_date, date}, _from, state) do
    {:reply, :ok, Map.put(state, :enrollment_date, date)}
  end

  def handle_call(:details, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:send_message, message}, from, state = %{client_pid: client_pid}) do
    Task.start(fn ->
      response = NodeClient.send_message(client_pid, message)
      GenServer.reply(from, response)
    end)

    {:noreply, state}
  end

  def handle_info(:connected, state = %{availability_history: history}) do
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

  def handle_info(
        {:DOWN, _ref, :process, _pid, _reason},
        state = %__MODULE__{
          client_pid: _client_pid,
          ip: ip,
          port: port,
          availability_history: history
        }
      ) do
    new_history =
      case history do
        <<>> ->
          <<0::1>>

        <<0::1, _::bitstring>> ->
          history

        <<1::1, _::bitstring>> ->
          <<0::1, history::bitstring>>
      end

    Process.sleep(1000)
    {:ok, pid} = NodeClient.start_link(ip: ip, port: port, parent_pid: self())
    Process.monitor(pid)

    new_state =
      state
      |> Map.put(:availability_history, new_history)
      |> Map.put(:availability, 0)
      |> Map.put(:average_availability, new_average_availability(new_history))
      |> Map.put(:client_pid, pid)

    {:noreply, new_state}
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
        Float.floor(available_times / bit_size(history), 1)
    end
  end

  @doc """
  Get the details of a node
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
    GenServer.call(via_tuple(first_public_key), {:update_basics, last_public_key, ip, port})
  end

  @doc """
  Update the network patch for a given node
  """
  @spec update_network_patch(node_public_key :: UnirisCrypto.key(), geo_patch :: binary()) :: :ok
  def update_network_patch(public_key, network_patch) do
    [{pid, _}] = Registry.lookup(NodeRegistry, public_key)
    GenServer.call(pid, {:update_network_patch, network_patch})
  end

  @doc """
  Update the average availability of the node and reset the history
  """
  @spec update_average_availability(
          node_public_key :: UnirisCrypto.key(),
          average_availability :: float()
        ) :: :ok
  def update_average_availability(public_key, avg_availability)
      when is_float(avg_availability) and avg_availability >= 0 and
             avg_availability <= 1 do
    GenServer.call(via_tuple(public_key), {:update_average_availability, avg_availability})
  end

  @doc """
  Mark the node as validator.
  """
  @spec authorize(UnirisCrypto.key() | __MODULE__.t()) :: :ok
  def authorize(public_key) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), :authorize)
  end

  def authorize(%__MODULE__{first_public_key: public_key}) do
    GenServer.call(via_tuple(public_key), :authorize)
  end

  @doc """
  Mark the node as ready
  """
  @spec set_ready(public_key :: UnirisCore.Crypto.key()) :: :ok
  def set_ready(public_key) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), :is_ready)
  end

  @spec set_enrollment_date(public_key :: UnirisCore.Crypto.key(), DateTime.t()) :: :ok
  def set_enrollment_date(public_key, date = %DateTime{}) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), {:set_enrollment_date, date})
  end

  def set_enrollment_date(public_key, nil) when is_binary(public_key) do
    :ok
  end

  @doc """
  Send message to a given node using the connected P2P client
  """
  @spec send_message(UnirisCore.Crypto.key(), term()) :: term()
  def send_message(public_key, message) do
    GenServer.call(via_tuple(public_key), {:send_message, message})
  end

  @spec via_tuple(id :: UnirisCrypto.key() | :inet.ip_address()) :: tuple()
  defp via_tuple(id) do
    {:via, Registry, {NodeRegistry, id}}
  end
end
