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
  alias UnirisCore.PubSub
  alias UnirisCore.Utils

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
    available?: true,
    average_availability: 1.0,
    availability_history: <<1::1>>,
    enrollment_date: nil,
    authorized?: false,
    ready?: false,
    ready_date: nil,
    authorization_date: nil
  ]

  @type t() :: %__MODULE__{
          first_public_key: binary(),
          last_public_key: binary(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          geo_patch: binary(),
          network_patch: binary(),
          available?: boolean(),
          average_availability: float(),
          availability_history: bitstring(),
          authorized?: boolean(),
          ready?: boolean(),
          enrollment_date: DateTime.t(),
          ready_date: DateTime.t(),
          authorization_date: DateTime.t()
        }

  @doc """
  Create a new process for the node registered it with its public keys and IP address
  A new process is spawwned and linked to establish the connection with the node.
  """
  def start_link(node = %__MODULE__{}) do
    GenServer.start_link(__MODULE__, node)
  end

  def init(
        node = %__MODULE__{
          ip: ip,
          first_public_key: first_public_key,
          last_public_key: last_public_key,
          geo_patch: geo_patch
        }
      ) do
    Registry.register(NodeRegistry, last_public_key, [])
    Registry.register(NodeRegistry, ip, [])
    Registry.register(NodeRegistry, first_public_key, [])

    node =
      if geo_patch == nil do
        patch = GeoPatch.from_ip(ip)
        %{node | geo_patch: patch, network_patch: patch}
      else
        node
      end

    {:ok, node}
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
    PubSub.notify_node_update(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call({:update_network_patch, network_patch}, _from, state) do
    new_state = Map.put(state, :network_patch, network_patch)
    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:update_average_availability, avg_availability}, _from, state) do
    new_state =
      state
      |> Map.put(:availability_history, <<>>)
      |> Map.put(:average_availability, avg_availability)

    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:authorize, date}, _from, state = %{authorized?: false}) do
    Logger.debug("Node #{Base.encode16(state.first_public_key)} is authorized")
    new_state = %{state | authorized?: true, authorization_date: Utils.truncate_datetime(date)}
    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:authorize, _date}, _from, state), do: {:reply, :ok, state}

  def handle_call({:set_ready, date}, _from, state = %{ready?: false}) do
    Logger.debug("Node #{Base.encode16(state.first_public_key)} is ready")
    new_state = %{state | ready?: true, ready_date: Utils.truncate_datetime(date)}
    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_ready, _date}, _from, state), do: {:reply, :ok, state}

  def handle_call({:set_enrollment_date, date}, _from, state = %{enrollment_date: nil}) do
    new_state = %{state | enrollment_date: Utils.truncate_datetime(date)}
    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_enrollment_date, _date}, _from, state), do: {:reply, :ok, state}

  def handle_call(:details, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:send_message, message}, from, state = %{ip: ip, port: port}) do
    %Task{ref: ref} = Task.async(fn -> NodeClient.send_message(ip, port, message) end)
    request = %{} |> Map.put(ref, from)
    {:noreply, Map.update(state, :requests, request, &Map.put(&1, ref, from))}
  end

  def handle_call(:available, _from, state) do
    new_state = %{state | available?: true}
    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:unavailable, _from, state) do
    new_state = %{state | available?: false}
    PubSub.notify_node_update(new_state)
    {:reply, :ok, new_state}
  end

  def handle_info({ref, result}, state = %{requests: requests}) do
    from = Map.get(requests, ref)
    GenServer.reply(from, result)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    new_state =
      state
      |> increase_availability
      |> Map.update!(:requests, &Map.delete(&1, ref))

    {:noreply, new_state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    Logger.error(reason)

    new_state =
      state
      |> reduce_availability
      |> Map.update!(:requests, &Map.delete(&1, ref))

    {:noreply, new_state}
  end

  defp increase_availability(state = %{availability_history: <<1::1, _::bitstring>>}) do
    state
  end

  defp increase_availability(state = %{availability_history: history = <<0::1, _::bitstring>>}) do
    new_history = <<1::1, history::bitstring>>
    Map.put(state, :availability_history, new_history)
  end

  defp reduce_availability(state = %{availability_history: <<0::1, _::bitstring>>}) do
    state
  end

  defp reduce_availability(state = %{availability_history: history = <<1::1, _::bitstring>>}) do
    new_history = <<0::1, history::bitstring>>
    Map.put(state, :availability_history, new_history)
  end

  # defp new_average_availability(history) do
  #   list = for <<view::1 <- history>>, do: view

  #   list
  #   |> Enum.frequencies()
  #   |> Map.get(1)
  #   |> case do
  #     nil ->
  #       0.0

  #     available_times ->
  #       Float.floor(available_times / bit_size(history), 1)
  #   end
  # end

  @doc """
  Get the details of a node
  """
  @spec details(node_public_key :: UnirisCore.Crypto.key()) :: __MODULE__.t()
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
          node_first_public_key :: UnirisCore.Crypto.key(),
          node_last_public_key :: UnirisCore.Crypto.key(),
          node_ip :: :inet.ip_address(),
          node_port :: :inet.port_number()
        ) :: :ok
  def update_basics(first_public_key, last_public_key, ip, port) do
    GenServer.call(via_tuple(first_public_key), {:update_basics, last_public_key, ip, port})
  end

  @doc """
  Mark the node as available
  """
  @spec available(UnirisCore.Crypto.key()) :: :ok
  def available(public_key) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), :available)
  end

  @doc """
  Mark the node as unavailable
  """
  @spec unavailable(UnirisCore.Crypto.key()) :: :ok
  def unavailable(public_key) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), :unavailable)
  end

  @doc """
  Update the network patch for a given node
  """
  @spec update_network_patch(node_public_key :: UnirisCore.Crypto.key(), geo_patch :: binary()) ::
          :ok
  def update_network_patch(public_key, network_patch) do
    GenServer.call(via_tuple(public_key), {:update_network_patch, network_patch})
  end

  @doc """
  Update the average availability of the node and reset the history
  """
  @spec update_average_availability(
          node_public_key :: UnirisCore.Crypto.key(),
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
  @spec authorize(node_public_key :: UnirisCore.Crypto.key(), authorization_date :: DateTime.t()) ::
          :ok
  def authorize(public_key, date = %DateTime{}) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), {:authorize, date})
  end

  @doc """
  Mark the node as ready
  """
  @spec set_ready(public_key :: UnirisCore.Crypto.key(), enrollment_date: DateTime.t()) :: :ok
  def set_ready(public_key, date = %DateTime{}) when is_binary(public_key) do
    GenServer.call(via_tuple(public_key), {:set_ready, date})
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

  @spec via_tuple(id :: UnirisCore.Crypto.key() | :inet.ip_address()) :: tuple()
  defp via_tuple(id) do
    {:via, Registry, {NodeRegistry, id}}
  end
end
