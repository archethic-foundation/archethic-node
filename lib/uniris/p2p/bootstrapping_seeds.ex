defmodule Uniris.P2P.BootstrappingSeeds do
  @moduledoc """
  Handle bootstrapping seeds lifecycle

  The networking seeds are firstly fetched either from file or environment variable (dev)

  The bootstrapping seeds support flushing updates
  """

  alias Uniris.Crypto

  alias Uniris.PubSub

  alias Uniris.P2P
  alias Uniris.P2P.GeoPatch
  alias Uniris.P2P.Node

  use GenServer

  require Logger

  @doc """
  Start the bootstrapping seeds holder

  Options:
  - File: path from the P2P bootstrapping seeds backup
  """
  @spec start_link(opts :: [file :: String.t()]) :: {:ok, pid()}
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
    hardcoded_seeds = Keyword.get(opts, :seeds, "")
    file = Keyword.get(opts, :file, "")

    seeds =
      case File.read(file) do
        {:ok, data} when data != "" ->
          extract_seeds(data)

        _ ->
          extract_seeds(hardcoded_seeds)
      end

    Logger.debug(
      "Bootstrapping seeds initialize with #{
        seeds |> Enum.map(&:inet.ntoa(&1.ip)) |> Enum.join(", ")
      }"
    )

    PubSub.register_to_node_update()

    {:ok, %{seeds: seeds, file: file}}
  end

  def handle_call(:list_seeds, _from, state = %{seeds: seeds}) do
    {:reply, seeds, state}
  end

  def handle_call({:new_seeds, []}, _from, state), do: {:reply, :ok, state}

  def handle_call({:new_seeds, _seeds}, _from, state = %{file: ""}),
    do: {:reply, :ok, state}

  def handle_call({:new_seeds, seeds}, _from, state = %{file: file}) do
    first_node_public_key = Crypto.node_public_key(0)

    seeds
    |> Enum.reject(&(&1.first_public_key == first_node_public_key))
    |> nodes_to_seeds
    |> flush_seeds(file)

    Logger.debug(
      "Bootstrapping seeds list refreshed with #{
        seeds |> Enum.map(&:inet.ntoa(&1.ip)) |> Enum.join(", ")
      }"
    )

    {:reply, :ok, %{state | seeds: seeds}}
  end

  def handle_info({:node_update, _}, state = %{file: file}) do
    top_nodes =
      P2P.list_nodes(authorized?: true, availability: :local)
      |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))

    top_nodes
    |> nodes_to_seeds
    |> flush_seeds(file)

    Logger.debug(
      "Bootstrapping seeds list refreshed with #{
        top_nodes |> Enum.map(&:inet.ntoa(&1.ip)) |> Enum.join(", ")
      }"
    )

    {:noreply, Map.put(state, :seeds, top_nodes)}
  end

  defp flush_seeds(_, ""), do: :ok

  defp flush_seeds(seeds_str, file) do
    File.mkdir_p(Path.dirname(file))
    File.write!(file, seeds_str, [:write])
  end

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
      acc ++ ["#{:inet_parse.ntoa(ip)}:#{port}:#{Base.encode16(public_key)}:#{transport}"]
    end)
    |> Enum.join("\n")
  end
end
