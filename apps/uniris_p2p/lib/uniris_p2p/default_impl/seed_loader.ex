defmodule UnirisP2P.DefaultImpl.SeedLoader do
  use GenServer

  alias UnirisP2P.Node

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, %{seeds: [], file: Keyword.get(opts, :seed_file)}, {:continue, :load_file}}
  end

  def handle_continue(:load_file, state = %{file: file}) do
    seeds =
      file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, ";"))
      |> Enum.flat_map(& &1)
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

    {:noreply, %{state | seeds: seeds}}
  end

  def handle_cast({:update, seeds}, state) do
    {:noreply, %{state | seeds: seeds}}
  end

  def handle_call(:list, _from, state = %{seeds: seeds}) do
    {:reply, seeds, state}
  end

  def terminate(_reason, _state = %{file: file, seeds: seeds}) do
    seeds_str =
      Enum.reduce(seeds, [], fn %Node{ip: ip, port: port, last_public_key: public_key}, acc ->
        acc ++ ["#{Tuple.to_list(ip) |> Enum.join(".")}:#{port}:#{public_key |> Base.encode16()}"]
      end)
      |> Enum.join("\n")

    File.write!(file, seeds_str, [:write])
    :ok
  end

  @spec list() :: list(Node.t())
  def list() do
    GenServer.call(__MODULE__, :list)
  end

  @spec update(list(Node.t())) :: :ok
  def update(seeds) do
    GenServer.cast(__MODULE__, {:update, seeds})
  end
end
