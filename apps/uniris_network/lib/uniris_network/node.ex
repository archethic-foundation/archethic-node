defmodule UnirisNetwork.Node do
  use GenServer

  @enforce_keys [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :availability,
    :average_availability
  ]
  defstruct [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :network_patch,
    :availability,
    :average_availability
  ]

  @ets_table :node_store

  @type patch() :: {0..9 | ?A..?F, 0..9 | ?A..?F, 0..9 | ?A..?F}

  @type t() :: %__MODULE__{
          first_public_key: binary(),
          last_public_key: binary(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          geo_patch: patch(),
          network_patch: patch(),
          availability: boolean(),
          average_availability: float()
        }

  def start_link(first_public_key: first_public_key, last_public_key: last_public_key, ip: ip, port: port) do
    GenServer.start_link(__MODULE__, [first_public_key, last_public_key, ip, port],
      name: via_tuple(first_public_key)
    )
  end

  def init([first_public_key, last_public_key, ip, port]) do
    Registry.register(UnirisNetwork.NodeRegistry, last_public_key, [])

    data = %__MODULE__{
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      ip: ip,
      port: port,
      geo_patch: UnirisNetwork.GeoPatch.from_ip(ip),
      average_availability: 0,
      availability: 0
    }

    Process.flag(:trap_exit, true)

    case :ets.lookup(@ets_table, first_public_key) do
      [{_, availability}] ->
        {:ok, Map.put(data, :availability, availability)}

      _ ->
        {:ok, data}
    end
  end

  def terminate(_reason, state = %{first_public_key: public_key, availability: availability}) do
    :ets.insert(@ets_table, {public_key, availability})
    :ok
  end

  def handle_cast(:available, state) do
    {:noreply, Map.put(state, :availability, 1)}
  end

  def handle_cast(:unavailable, state) do
    {:noreply, Map.put(state, :availability, 0)}
  end

  def handle_call(:details, from, state) do
    {:reply, state, state}
  end

  def handle_cast({:update_basics, last_public_key, ip, port}, state) do
    new_state = state
    |> Map.put(:last_public_key, last_public_key)
    |> Map.put(:ip, ip)
    |> Map.put(:port, port)

    {:noreply, new_state}
  end

  def handle_cast({:update_network_patch, network_patch}, state) do
    {:noreply, Map.put(state, :network_patch, network_patch)}
  end

  @spec available(binary()) :: :ok
  def available(node_public_key) when is_binary(node_public_key) do
    GenServer.cast(via_tuple(node_public_key), :available)
  end

  @spec unavailable(binary()) :: :ok
  def unavailable(node_public_key) when is_binary(node_public_key) do
    GenServer.cast(via_tuple(node_public_key), :unavailable)
  end

  @spec details(binary()) :: __MODULE__.t()
  def details(node_public_key) when is_binary(node_public_key) do
    GenServer.call(via_tuple(node_public_key), :details)
  end

  @spec update_basics(binary(), binary(), :inet.ip_address(), :inet.port_number()) :: :ok
  def update_basics(first_public_key, last_public_key, ip, port) do
    GenServer.cast(via_tuple(first_public_key), {:update_basics, last_public_key, ip, port})
  end

  @spec update_network_patch(binary(), binary()) :: :ok
  def update_network_patch(public_key, network_patch) when is_binary(network_patch) do
    [{pid, _}] = Registry.lookup(UnirisNetwork.NodeRegistry, public_key)
    GenServer.cast(pid, {:update_network_patch, network_patch})
  end

  defp via_tuple(public_key) do
    {:via, Registry, {UnirisNetwork.NodeRegistry, public_key}}
  end
end
