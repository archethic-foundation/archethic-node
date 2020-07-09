defmodule UnirisCore.P2P.BootstrapingSeeds do
  @moduledoc false

  alias UnirisCore.Crypto
  alias UnirisCore.P2P.Node

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list() :: list(Node.t())
  def list, do: GenServer.call(__MODULE__, :list_seeds)

  @spec update(list(Node.t())) :: :ok
  def update(seeds), do: GenServer.call(__MODULE__, {:new_seeds, seeds})

  def init(opts) do
    case Application.get_env(:uniris_core, __MODULE__)[:seeds] do
      seeds_str when is_binary(seeds_str) ->
        seeds = extract_seeds(seeds_str)
        {:ok, %{seeds: seeds, file: ""}}

      nil ->
        case Keyword.get(opts, :file) do
          nil ->
            {:ok, %{seeds: [], file: ""}}

          file ->
            seeds =
              file
              |> File.read!()
              |> extract_seeds

            {:ok, %{seeds: seeds, file: file}}
        end
    end
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
    |> Enum.reduce([], fn %Node{ip: ip, port: port, first_public_key: public_key}, acc ->
      acc ++ ["#{stringify_ip(ip)}:#{port}:#{public_key |> Base.encode16()}"]
    end)
    |> Enum.join("\n")
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
end
