defmodule Mix.Tasks.Uniris.Testnet do
  @shortdoc "Creates and runs several nodes in testnet"
  @subnet "172.16.16.0/24"
  @network "testnet"
  @image "uniris-testnet"
  @output "docker-compose.json"
  @persist false
  @run true
  # hardcoded
  @p2p_port 3002
  @web_port 4000
  @moduledoc """
  This task generates `docker-compose.json` and optionally runs sevaral nodes in testnet.

  ## Command line options

    * `-h`, `--help` - show this help
    * `-o`, `--output` - use output file name, default "#{@output}"
    * `-n`, `--network` - use network name, default "#{@network}"
    * `-s`, `--subnet` - use subnet for the network, default "#{@subnet}"
    * `-p`, `--persist` - mount data{n} to /opt/data, default "#{@persist}"
    * `-i`, `--image` - use image name for built container, default "#{@image}"
    * `--run/--no-run` - atuomatically run `docker-compose up`, default "#{@run}"

  ## Command line arguments
    * `seeds` - list of seeds

  ## Example

  ```sh
  mix uniris.testnet $(seq --format "seed%g" --separator " " 5)
  ```

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             output: :string,
             persist: :boolean,
             network: :string,
             subnet: :string,
             image: :string,
             run: :boolean
           ],
           aliases: [h: :help, o: :output, p: :persist, n: :network, s: :subnet, i: :image]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, seeds} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          run(seeds, parsed)
        end
    end
  end

  defp run(seeds, opts) do
    output = Keyword.get(opts, :output, @output)

    Mix.shell().info("Generating `#{output}` for #{length(seeds)} nodes")

    {services, networks} = from(seeds, opts)

    compose =
      %{version: "3.9", services: services, networks: networks}
      |> Jason.encode!(pretty: true)

    File.write!(output, compose)

    unless !Keyword.get(opts, :run, @run) do
      Mix.shell().cmd("docker-compose -f #{output} up")
    end
  end

  defmodule Subnet do
    @moduledoc """
    Represents subnet
    """

    defstruct ~w(address mask)a

    @type t :: %Subnet{address: :inet.ip_address(), mask: non_neg_integer()}

    @doc """
    Parse

    ## Example

        iex> "192.168.0.1/24" |> Subnet.parse()
        {:ok, %Subnet{address: {192,168,0,1}, mask: 24}}

        iex> "2001:db8::/64" |> Subnet.parse()
        {:ok, %Subnet{address: {8193,3512,0,0,0,0,0,0}, mask: 64}}

    """
    @spec parse(binary()) :: {:ok, t} | {:error, term}
    def parse(subnet) when is_binary(subnet) do
      with [address, mask] <- String.split(subnet, "/", parts: 2),
           {mask, ""} <- Integer.parse(mask),
           {:ok, address} <- :inet.parse_address(String.to_charlist(address)) do
        {:ok, %Subnet{address: address, mask: mask}}
      else
        _ ->
          {:error, :einval}
      end
    end

    @doc """
    Same as `Subnet.parse/1` but raises `ArgumentError`

    ## Example

        iex> "192.168.0.1/24" |> Subnet.parse!()
        %Subnet{address: {192,168,0,1}, mask: 24}

        iex> "abc/24" |> Subnet.parse!()
        ** (ArgumentError) abc/24 is not a subnet

    """

    @spec parse!(binary()) :: t()
    def parse!(subnet) when is_binary(subnet) do
      case parse(subnet) do
        {:ok, subnet} -> subnet
        _ -> raise(ArgumentError, message: "#{subnet} is not a subnet")
      end
    end

    @doc """
    Returns string representing ip address at the given offset, assuming that
    the gateway address is the first ip address in the subnet range.

    There is no real ip calculation involved, the function simply changes the
    last number in the ip address tuple.

    ## Example

        iex> "192.168.0.1/24" |> Subnet.parse() |> elem(1) |> Subnet.at(10)
        "192.168.0.11"

        iex> "2001:db8::/64" |> Subnet.parse() |> elem(1) |> Subnet.at(10)
        "2001:db8::b"

    """
    @spec at(t(), non_neg_integer()) :: String.t()
    def at(%Subnet{address: address = {_, _, _, _}}, offset) do
      address |> put_elem(3, offset + 1) |> :inet.ntoa() |> to_string
    end

    def at(%Subnet{address: address = {_, _, _, _, _, _, _, _}}, offset) do
      address |> put_elem(7, offset + 1) |> :inet.ntoa() |> to_string
    end
  end

  defp from(seeds, opts) do
    image = Keyword.get(opts, :image, @image)
    persist = Keyword.get(opts, :persist, @persist)
    network = Keyword.get(opts, :network, @network)
    subnet = Keyword.get(opts, :subnet, @subnet)
    base = Subnet.parse!(subnet)
    ip = fn i -> base |> Subnet.at(i) end

    services =
      seeds
      |> Enum.scan([], fn seed, acc -> [seed | acc] end)
      |> Enum.with_index(1)
      |> Enum.map(&to_node(&1, persist, image, network, ip))
      |> Enum.into(%{})

    networks = %{
      Keyword.get(opts, :network, @network) => %{
        ipam: %{driver: :default, config: [%{subnet: subnet}]}
      }
    }

    {services, networks}
  end

  defp to_node({[seed], 1}, persist?, image, network, ip) do
    {"node1",
     %{
       build: %{context: ".", args: %{skip_tests: 1, MIX_ENV: :dev}},
       image: image,
       environment: %{
         "UNIRIS_CRYPTO_SEED" => seed,
         "UNIRIS_P2P_SEEDS" => seeder(ip.(1), seed)
       },
       networks: %{network => %{ipv4_address: ip.(1)}}
     }
     |> mount(persist?, 1)}
  end

  defp to_node({[seed | seeds], n}, persist?, image, network, ip) do
    seeders =
      seeds
      |> Enum.reverse()
      |> Enum.with_index(1)
      |> Enum.map(fn {s, i} -> seeder(ip.(i), s) end)
      |> Enum.join("\n")

    {"node#{n}",
     %{
       image: image,
       depends_on: ["node1"],
       environment: %{
         "UNIRIS_CRYPTO_SEED" => seed,
         "UNIRIS_P2P_SEEDS" => seeders
       },
       volumes: ["./scripts/wait-for-node.sh:/wait.sh:ro"],
       command: ["/wait.sh", "http://node1:#{@web_port}/up", "./bin/uniris_node", "foreground"],
       networks: %{network => %{ipv4_address: ip.(n)}}
     }
     |> mount(persist?, n)}
  end

  defp pubkey(seed), do: seed |> Uniris.Crypto.derive_keypair(0) |> elem(0) |> Base.encode16()

  defp seeder(ip, seed), do: "#{ip}:#{@p2p_port}:#{pubkey(seed)}:tcp"

  defp mount(m, false, _), do: m

  defp mount(m, true, n) do
    mount = ["./data#{n}:/opt/data"]

    m
    |> Map.update(:volumes, mount, fn v -> mount ++ v end)
    |> Map.update!(:environment, fn e -> Map.put(e, "UNIRIS_MUT_DIR", "/opt/data") end)
  end
end
