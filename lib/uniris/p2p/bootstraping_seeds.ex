defmodule Uniris.P2P.BootstrapingSeeds do
  @moduledoc """
  Handle bootstraping seeds lifecyle

  The networking seeds are firstly fetched either from file or environment variable (dev)

  The bootstraping seeds support flushing updates
  """

  alias Uniris.Crypto
  alias Uniris.P2P.Node
  alias Uniris.Storage.Memory.NetworkLedger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  List the current bootstraping network seeds
  """
  @spec list() :: list(Node.t())
  def list, do: GenServer.call(__MODULE__, :list_seeds)

  @doc """
  Update the bootstraping network seeds and flush them
  """
  @spec update(list(Node.t())) :: :ok
  def update(seeds), do: GenServer.call(__MODULE__, {:new_seeds, seeds})

  def init(opts) do
    {seeds, file} =
      case Application.get_env(:uniris, __MODULE__)[:seeds] do
        nil ->
          parse_opts(opts)

        seeds_str ->
          seeds = extract_seeds(seeds_str)
          {seeds, ""}
      end

    load_seeds_into_ledger(seeds)
    {:ok, %{seeds: seeds, file: file}}
  end

  defp parse_opts(opts) do
    case Keyword.get(opts, :file) do
      nil ->
        {[], ""}

      file ->
        seeds =
          file
          |> File.read!()
          |> extract_seeds

        {seeds, file}
    end
  end

  defp load_seeds_into_ledger(seeds) do
    seeds
    |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
    |> Enum.each(&NetworkLedger.add_node_info/1)
  end

  def handle_call(:list_seeds, _from, state = %{seeds: seeds}) do
    {:reply, seeds, state}
  end

  def handle_call({:new_seeds, []}, _from, state), do: {:reply, :ok, state}

  def handle_call({:new_seeds, _seeds}, _from, state = %{file: ""}),
    do: {:reply, :ok, state}

  def handle_call({:new_seeds, seeds}, _from, state = %{file: file}) do
    seeds
    |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
    |> nodes_to_seeds
    |> case do
      "" ->
        :ok

      seeds_str ->
        File.write!(file, seeds_str, [:write])
    end

    {:reply, :ok, %{state | seeds: seeds}}
  end

  defp extract_seeds(seeds_str) do
    seeds_str
    |> String.split("\n", trim: true)
    |> Enum.map(fn seed ->
      [ip, port, public_key] = String.split(seed, ":")
      {:ok, ip} = ip |> String.to_charlist() |> :inet.parse_address()

      %Node{
        ip: ip,
        port: String.to_integer(port),
        last_public_key: public_key |> Base.decode16!(),
        first_public_key: public_key |> Base.decode16!()
      }
    end)
  end

  defp stringify_ip(ip), do: :inet_parse.ntoa(ip)

  @doc """
  Convert a list of nodes into a P2P seeds list
  """
  @spec nodes_to_seeds(list(Node.t())) :: binary()
  def nodes_to_seeds(nodes) when is_list(nodes) do
    nodes
    |> Enum.reduce([], fn %Node{ip: ip, port: port, first_public_key: public_key}, acc ->
      acc ++ ["#{stringify_ip(ip)}:#{port}:#{public_key |> Base.encode16()}"]
    end)
    |> Enum.join("\n")
  end
end
