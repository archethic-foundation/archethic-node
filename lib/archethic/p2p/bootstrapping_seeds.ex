defmodule Archethic.P2P.BootstrappingSeeds do
  @moduledoc """
  Handle bootstrapping seeds lifecycle

  The networking seeds are firstly fetched either from a previous flush or from an environment variable

  The bootstrapping seeds support flushing updates
  """

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.PubSub

  alias Archethic.P2P
  alias Archethic.P2P.GeoPatch
  alias Archethic.P2P.Node

  use GenServer
  @vsn 1

  require Logger

  @type options :: [
          genesis_seeds: binary()
        ]

  @doc """
  Start the bootstrapping seeds holder
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  List the current bootstrapping network seeds
  """
  @spec list() :: list(Node.t())
  def list, do: GenServer.call(__MODULE__, :list_seeds)

  @doc """
  Update the bootstrapping network seeds and flush them
  """
  @spec update(list(Node.t())) :: :ok
  def update(seeds), do: GenServer.call(__MODULE__, {:new_seeds, seeds})

  def init(opts) do
    genesis_seeds = Keyword.get(opts, :genesis_seeds, "")

    seeds =
      case DB.get_bootstrap_info("bootstrapping_seeds") do
        nil ->
          if genesis_seeds == "" do
            raise "Missing genesis seeds"
          end

          DB.set_bootstrap_info("bootstrapping_seeds", genesis_seeds)
          extract_seeds(genesis_seeds)

        seeds ->
          extract_seeds(seeds)
      end

    Logger.info(
      "Bootstrapping seeds initialize with #{Enum.map_join(seeds, ", ", &:inet.ntoa(&1.ip))}"
    )

    PubSub.register_to_node_update()

    {:ok, %{seeds: seeds}}
  end

  def handle_call(:list_seeds, _from, state = %{seeds: seeds}) do
    {:reply, seeds, state}
  end

  def handle_call({:new_seeds, []}, _from, state), do: {:reply, :ok, state}

  def handle_call({:new_seeds, seeds}, _from, state) do
    seeds_stringified =
      seeds
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))
      |> nodes_to_seeds()

    DB.set_bootstrap_info("bootstrapping_seeds", seeds_stringified)

    Logger.info(
      "Bootstrapping seeds list refreshed with #{Enum.map_join(seeds, ", ", &Node.endpoint/1)}"
    )

    {:reply, :ok, %{state | seeds: seeds}}
  end

  def handle_info({:node_update, %Node{authorized?: true}}, state) do
    top_nodes =
      Enum.reject(
        P2P.authorized_and_available_nodes(),
        &(&1.first_public_key == Crypto.first_node_public_key())
      )

    if Enum.empty?(top_nodes) do
      {:noreply, state}
    else
      DB.set_bootstrap_info("bootstrapping_seeds", nodes_to_seeds(top_nodes))

      Logger.debug(
        "Bootstrapping seeds list refreshed with #{Enum.map_join(top_nodes, ", ", &Node.endpoint/1)}"
      )

      {:noreply, Map.put(state, :seeds, top_nodes)}
    end
  end

  def handle_info({:node_update, _}, state), do: {:noreply, state}

  defp extract_seeds(seeds_str) do
    seeds_str
    |> String.split("\n", trim: true)
    |> Enum.map(fn seed ->
      [ip, port, public_key, transport] = String.split(seed, ":")
      {:ok, ip} = ip |> String.to_charlist() |> :inet.parse_address()

      patch = GeoPatch.from_ip(ip)

      %Node{
        ip: ip,
        port: String.to_integer(port),
        last_public_key: Base.decode16!(public_key, case: :mixed),
        first_public_key: Base.decode16!(public_key, case: :mixed),
        geo_patch: patch,
        network_patch: patch,
        transport:
          case transport do
            "tcp" ->
              :tcp
          end
      }
    end)
  end

  @doc """
  Convert a list of nodes into a P2P seeds list

  ## Examples

      iex> [ %Node{ip: {127, 0, 0, 1}, port: 3000, first_public_key: "mykey", transport: :tcp} ]
      ...> |> BootstrappingSeeds.nodes_to_seeds()
      "127.0.0.1:3000:6D796B6579:tcp"
  """
  @spec nodes_to_seeds(list(Node.t())) :: binary()
  def nodes_to_seeds(nodes) when is_list(nodes) do
    nodes
    |> Enum.reduce([], fn %Node{
                            ip: ip,
                            port: port,
                            first_public_key: public_key,
                            transport: transport
                          },
                          acc ->
      acc ++
        ["#{:inet_parse.ntoa(ip)}:#{port}:#{Base.encode16(public_key)}:#{transport}"]
    end)
    |> Enum.join("\n")
  end
end
