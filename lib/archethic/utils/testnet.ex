defmodule ArchEthic.Testnet do
  @moduledoc """
  ArchEthic Testnet Generator
  """

  defmodule Subnet do
    @moduledoc """
    Represents subnet
    """
    alias __MODULE__

    defstruct ~w(address mask)a

    @type t :: %Subnet{address: :inet.ip_address(), mask: non_neg_integer()}

    @doc """
    Parse string

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
    Returns string that represents an ip address at the given offset in the
    subnet range.

    There is no real ip calculation involved, the function simply changes the
    last number in the ip address tuple.

    ## Example

        iex> "192.168.0.1/24" |> Subnet.parse() |> elem(1) |> Subnet.at(10)
        "192.168.0.10"

        iex> "2001:db8::/64" |> Subnet.parse() |> elem(1) |> Subnet.at(10)
        "2001:db8::a"

    """
    @spec at(t(), non_neg_integer()) :: String.t()
    def at(%Subnet{address: address = {_, _, _, _}}, offset) do
      address |> put_elem(3, offset) |> :inet.ntoa() |> to_string
    end

    def at(%Subnet{address: address = {_, _, _, _, _, _, _, _}}, offset) do
      address |> put_elem(7, offset) |> :inet.ntoa() |> to_string
    end

    @doc """
    Returns next subnet.

    ## Example

        iex> "192.168.0.0/24" |> Subnet.next()
        "192.168.1.0/24"

        iex> "2001:db8::/64" |> Subnet.next()
        "2001:db8:1::/64"
    """
    @spec next(t() | String.t()) :: String.t()
    def next(%Subnet{address: address, mask: mask}) do
      x = elem(address, 2)
      "#{address |> put_elem(2, x + 1) |> :inet.ntoa() |> to_string}/#{mask}"
    end

    def next(subnet_string) when is_binary(subnet_string) do
      with {:ok, subnet} <- parse(subnet_string) do
        Subnet.next(subnet)
      end
    end
  end

  alias ArchEthic.Crypto

  defp p2p_port, do: Application.get_env(:archethic, ArchEthic.P2P.Endpoint)[:port]
  defp web_port, do: Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]

  @validator Mix.Project.config()[:escript][:name]
  @validator_ip 220
  @collector_ip 200

  @type testnet :: [Path.t() | {Path.t(), String.t() | map()}]

  @doc """
  Given a list of seeds and options generates a list of folders and files
  required to start testnet with docker-compose. Folders represented as strings
  and files represented as tuples of filename and its content. If file content
  is a map it is serialised as json.

  ## Options

    * `:image` - image to use for archethic node
    * `:persist` - add mounts for mutable data
    * `:subnet` - network subnet
    * `:src` - path to the source code

  ## Example
    iex> Testnet.from(["seed1", "seed2", "seed3"], [image: "i", persist: true, subnet: "1.2.3.0/24", src: "c"])
    [".data1", ".data2", ".data3", ".collector",
      {".collector/prometheus.yml",
        "global:\\n" <>
        "  scrape_interval: 5s\\n" <>
        "  scrape_timeout: 5s\\n\\n" <>
        "scrape_configs:\\n" <>
        "- job_name: testnet\\n" <>
        "  static_configs:\\n" <>
        "  - targets:\\n" <>
        "    - node1:#4002\\n" <>
        "    - node2:#4002\\n" <>
        "    - node3:#4002\\n\\n"},
      {"docker-compose.json", %{
        version: "3.9",
          networks: %{:net => %{ipam: %{config: [%{subnet: "1.2.3.0/24"}], driver: :default}}},
          services: %{
            "node1" => %{
              build: %{args: %{MIX_ENV: :dev, skip_tests: 1}, context: "c"},
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "seed1",
                "ARCHETHIC_MUT_DIR" => "/opt/data",
                "ARCHETHIC_P2P_SEEDS" => "1.2.3.2:3002:009D421F8ACC11F7E25EC515732ECB7E3E38109118EC409701930D7A892E913428:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.2"},
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.2"}},
              volumes: [".data1:/opt/data"]},
            "node2" => %{
              command: ["/wait.sh", "http://node1:4002/up", "./bin/archethic_node", "foreground"],
              depends_on: ["node1"],
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "seed2",
                "ARCHETHIC_MUT_DIR" => "/opt/data",
                "ARCHETHIC_P2P_SEEDS" => "1.2.3.2:3002:009D421F8ACC11F7E25EC515732ECB7E3E38109118EC409701930D7A892E913428:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.3"},
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.3"}},
              volumes: [".data2:/opt/data", "c/scripts/wait-for-node.sh:/wait.sh:ro"]},
            "node3" => %{
              command: ["/wait.sh", "http://node1:4002/up", "./bin/archethic_node", "foreground"],
              depends_on: ["node1"],
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "seed3",
                "ARCHETHIC_MUT_DIR" => "/opt/data",
                "ARCHETHIC_P2P_SEEDS" => "1.2.3.2:3002:009D421F8ACC11F7E25EC515732ECB7E3E38109118EC409701930D7A892E913428:tcp\\n" <>
                                      "1.2.3.3:3002:00FBB0C05A9315CFC636A5AF30A7842E4144D2472D1FED1CA2CE401EB5056AB095:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.4"},
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.4"}},
              volumes: [".data3:/opt/data", "c/scripts/wait-for-node.sh:/wait.sh:ro"]},
            "collector" => %{
              image: "prom/prometheus",
              networks: %{:net => %{ipv4_address: "1.2.3.#{@collector_ip}"}},
              volumes: [".collector/prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
            },
            "validator" => %{
              command: ["/testnet/#{@validator}", "node1", "node2", "node3"],
              image: "elixir:alpine",
              networks: %{:net => %{ipv4_address: "1.2.3.#{@validator_ip}"}},
              stdin_open: true,
              volumes: ["./:/testnet"]
            }
          }
        }
      }
    ]
  """
  @spec from([String.t()], Keyword.t()) :: testnet()
  def from(seeds, opts) do
    src = Keyword.fetch!(opts, :src)
    image = Keyword.fetch!(opts, :image)
    persist = Keyword.fetch!(opts, :persist)
    subnet = Keyword.fetch!(opts, :subnet)

    base = Subnet.parse!(subnet)
    ip = fn i -> Subnet.at(base, i) end

    services = nodes_from(seeds, src, image, persist, ip)
    uninodes = Map.keys(services)

    folders =
      services
      |> Enum.flat_map(fn
        {_, %{volumes: vs}} ->
          for v = <<".", _::binary>> <- vs, do: v |> String.split(":") |> Enum.at(0)

        {_, _} ->
          []
      end)

    networks = %{:net => %{ipam: %{driver: :default, config: [%{subnet: subnet}]}}}

    services =
      services
      |> Map.put("collector", %{
        image: "prom/prometheus",
        networks: %{:net => %{ipv4_address: ip.(@collector_ip)}},
        volumes: [".collector/prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
      })
      |> Map.put("validator", %{
        image: "elixir:alpine",
        command: ["/testnet/#{@validator}" | uninodes],
        networks: %{:net => %{ipv4_address: ip.(@validator_ip)}},
        volumes: ["./:/testnet"],
        stdin_open: true
      })

    compose = %{version: "3.9", services: services, networks: networks}

    folders ++
      [
        ".collector",
        {".collector/prometheus.yml", prometheus_config(uninodes)},
        {"docker-compose.json", compose}
      ]
  end

  @doc """
  Creates files and folder required to run testnet.
  """
  @spec create!(testnet(), Path.t()) :: :ok
  def create!(testnet, path) do
    Enum.each(testnet, fn
      folder when is_binary(folder) ->
        :ok = File.mkdir_p!(Path.join(path, folder))

      {file, content} when is_binary(content) ->
        :ok = File.write!(Path.join(path, file), content)

      {file, json} when is_map(json) ->
        :ok = File.write!(Path.join(path, file), Jason.encode_to_iodata!(json, pretty: true))
    end)
  end

  defp prometheus_config(nodes) do
    targets = nodes |> Enum.map(&"    - #{&1}:#{web_port()}\n") |> Enum.join()

    """
    global:
      scrape_interval: 5s
      scrape_timeout: 5s

    scrape_configs:
    - job_name: testnet
      static_configs:
      - targets:
    #{targets}
    """
  end

  defp nodes_from(seeds, src, image, persist, ip) do
    seeds
    |> Enum.scan([], fn seed, acc -> [seed | acc] end)
    |> Enum.with_index(1)
    |> Enum.map(&to_node(&1, persist, src, image, ip))
    |> Enum.into(%{})
  end

  defp to_node({[seed], 1}, persist?, src, image, ip) do
    {"node1",
     %{
       build: %{context: src, args: %{skip_tests: 1, MIX_ENV: :dev}},
       image: image,
       environment: %{
         "ARCHETHIC_CRYPTO_SEED" => seed,
         "ARCHETHIC_P2P_SEEDS" => seeder(ip.(1 + 1), seed),
         "ARCHETHIC_STATIC_IP" => ip.(1 + 1)
       },
       networks: %{:net => %{ipv4_address: ip.(1 + 1)}}
     }
     |> mount(persist?, 1)}
  end

  defp to_node({[seed | seeds], n}, persist?, src, image, ip) do
    seeders =
      seeds
      |> Enum.reverse()
      |> Enum.with_index(1)
      |> Enum.map(fn {s, i} -> seeder(ip.(i + 1), s) end)
      |> Enum.join("\n")

    {"node#{n}",
     %{
       image: image,
       depends_on: ["node1"],
       environment: %{
         "ARCHETHIC_CRYPTO_SEED" => seed,
         "ARCHETHIC_P2P_SEEDS" => seeders,
         "ARCHETHIC_STATIC_IP" => ip.(n + 1)
       },
       networks: %{:net => %{ipv4_address: ip.(n + 1)}},
       volumes: ["#{src}/scripts/wait-for-node.sh:/wait.sh:ro"],
       command: [
         "/wait.sh",
         "http://node1:#{web_port()}/up",
         "./bin/archethic_node",
         "foreground"
       ]
     }
     |> mount(persist?, n)}
  end

  defp pubkey(seed), do: seed |> Crypto.derive_keypair(0) |> elem(0) |> Base.encode16()

  defp seeder(addr, seed), do: "#{addr}:#{p2p_port()}:#{pubkey(seed)}:tcp"

  defp mount(m, false, _), do: m

  defp mount(m, true, n) do
    mount = [".data#{n}:/opt/data"]
    envir = %{"ARCHETHIC_MUT_DIR" => "/opt/data"}

    m
    |> Map.update(:volumes, mount, fn v -> mount ++ v end)
    |> Map.update(:environment, envir, fn e -> Map.merge(e, envir) end)
  end
end
