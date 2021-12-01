defmodule ArchEthic.Utils.Testnet do
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

  defp p2p_port, do: Application.get_env(:archethic, ArchEthic.P2P.Listener)[:port]
  defp web_port, do: Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]

  @validator_ip 220
  @bench_ip 221
  @collector_ip 200

  @type testnet :: [Path.t() | {Path.t(), String.t() | map()}]

  @doc """
  Given a number of nodes and options generates a list of folders and files
  required to start testnet with docker-compose. Folders represented as strings
  and files represented as tuples of filename and its content. If file content
  is a map it is serialised as json.

  ## Options

    * `:image` - image to use for archethic node
    * `:subnet` - network subnet
    * `:src` - path to the source code

  ## Example
    iex> Testnet.from(3, [image: "i", persist: true, subnet: "1.2.3.0/24", src: "c"])
    [ {".prometheus.yml",
        "global:\\n" <>
        "  scrape_interval: 5s\\n" <>
        "  scrape_timeout: 5s\\n\\n" <>
        "scrape_configs:\\n" <>
        "- job_name: testnet\\n" <>
        "  static_configs:\\n" <>
        "  - targets:\\n" <>
        "    - node1:4002\\n" <>
        "    - node2:4002\\n" <>
        "    - node3:4002\\n\\n"},
      {"docker-compose.json", %{
        version: "3.9",
          networks: %{:net => %{ipam: %{config: [%{subnet: "1.2.3.0/24"}], driver: :default}}},
          services: %{
            "node1" => %{
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "node1",
                "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => "1.2.3.2:3002:00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.2",
                "ARCHETHIC_DB_HOST" => "scylladb1:9042"
              },
              image: "i",
              build: %{ context: "c"},
              networks: %{:net => %{ipv4_address: "1.2.3.2"}},
              command: [
                "/wait-for-tcp.sh",
                "scylladb1:9042",
                "--timeout=0",
                "--strict",
                "--",
                "./bin/archethic_node",
                "foreground"
              ],
              volumes: [
                "c/scripts/wait-for-tcp.sh:/wait-for-tcp.sh:ro"
              ]
            },
            "node2" => %{
              depends_on: ["node1"],
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "node2",
                "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => "1.2.3.2:3002:00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.3",
                "ARCHETHIC_DB_HOST" => "scylladb2:9042"
              },
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.3"}},
              volumes: [
                "c/scripts/wait-for-tcp.sh:/wait-for-tcp.sh:ro",
                "c/scripts/wait-for-node.sh:/wait-for-node.sh:ro"
              ],
              command: [
                "/wait-for-tcp.sh",
                "scylladb2:9042",
                "--timeout=0",
                "--strict", "--",
                "/wait-for-node.sh",
                "http://node1:4002/up",
                "./bin/archethic_node",
                "foreground"
              ]
            },
            "node3" => %{
              depends_on: ["node1"],
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "node3",
                "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => "1.2.3.2:3002:00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.4",
                "ARCHETHIC_DB_HOST" => "scylladb3:9042"
              },
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.4"}},
              volumes: [
                "c/scripts/wait-for-tcp.sh:/wait-for-tcp.sh:ro",
                "c/scripts/wait-for-node.sh:/wait-for-node.sh:ro"
              ],
              command: [
                "/wait-for-tcp.sh",
                "scylladb3:9042",
                "--timeout=0",
                "--strict", "--",
                "/wait-for-node.sh",
                "http://node1:4002/up",
                "./bin/archethic_node",
                "foreground"
              ]
            },
            "collector" => %{
              image: "prom/prometheus",
              networks: %{:net => %{ipv4_address: "1.2.3.#{@collector_ip}"}},
              volumes: [".prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
            },
            "validator" => %{
              image: "archethic-node:latest",
              environment: %{
                "ARCHETHIC_MUT_DIR" => "/opt/data"
              },
              command: ["./bin/archethic_node", "regression_test", "--validate", "node1", "node2", "node3"],
              volumes: [
                "./validator_data/:/opt/data"
              ],
              profiles: ["validate"],
              networks: %{:net => %{ipv4_address: "1.2.3.#{@validator_ip}"}},
            },
            "bench" => %{
              image: "archethic-node:latest",
              environment: %{
                "ARCHETHIC_MUT_DIR" => "/opt/data"
              },
              command: ["./bin/archethic_node", "regression_test", "--bench", "node1", "node2", "node3"],
              volumes: [
                "./bench_data/:/opt/data"
              ],
              profiles: ["validate"],
              networks: %{ :net => %{ipv4_address: "1.2.3.#{@bench_ip}"}}
            },
            "scylladb1" => %{
              image: "scylladb/scylla",
              networks: %{:net => %{ipv4_address: "1.2.3.51"}}
            },
            "scylladb2" => %{
              image: "scylladb/scylla",
              networks: %{:net => %{ipv4_address: "1.2.3.52"}}
            },
            "scylladb3" => %{
              image: "scylladb/scylla",
              networks: %{:net => %{ipv4_address: "1.2.3.53"}}
            }
          }
        }
      }
    ]
  """
  @spec from(non_neg_integer(), Keyword.t()) :: testnet()
  def from(nb_nodes, opts) do
    src = Keyword.fetch!(opts, :src)
    image = Keyword.fetch!(opts, :image)
    subnet = Keyword.fetch!(opts, :subnet)

    base = Subnet.parse!(subnet)
    ip = fn i -> Subnet.at(base, i) end

    services = nodes_from(nb_nodes, src, image, ip)
    uninodes = Map.keys(services)

    networks = %{:net => %{ipam: %{driver: :default, config: [%{subnet: subnet}]}}}

    databases =
      1..nb_nodes
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, "scylladb#{i}", %{
          image: "scylladb/scylla",
          networks: %{:net => %{ipv4_address: ip.(i + 50)}}
        })
      end)

    services =
      services
      |> Map.put("collector", %{
        image: "prom/prometheus",
        networks: %{:net => %{ipv4_address: ip.(@collector_ip)}},
        volumes: [".prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
      })
      |> Map.put("validator", %{
        image: "archethic-node:latest",
        environment: %{
          "ARCHETHIC_MUT_DIR" => "/opt/data"
        },
        command: ["./bin/archethic_node", "regression_test", "--validate" | uninodes],
        volumes: [
          "./validator_data/:/opt/data"
        ],
        profiles: ["validate"],
        networks: %{:net => %{ipv4_address: ip.(@validator_ip)}}
      })
      |> Map.put("bench", %{
        image: "archethic-node:latest",
        environment: %{
          "ARCHETHIC_MUT_DIR" => "/opt/data"
        },
        command: ["./bin/archethic_node", "regression_test", "--bench" | uninodes],
        volumes: [
          "./bench_data/:/opt/data"
        ],
        profiles: ["validate"],
        networks: %{:net => %{ipv4_address: ip.(@bench_ip)}}
      })
      |> Map.merge(databases)

    compose = %{version: "3.9", services: services, networks: networks}

    [
      {".prometheus.yml", prometheus_config(uninodes)},
      {"docker-compose.json", compose}
    ]
  end

  @doc """
  Creates files and folder required to run testnet.
  """
  @spec create!(testnet(), Path.t()) :: :ok
  def create!(testnet, path) do
    File.mkdir_p!(path)

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
    targets = Enum.map_join(nodes, &"    - #{&1}:#{web_port()}\n")

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

  defp nodes_from(nb_nodes, src, image, ip) do
    1..nb_nodes
    |> Enum.map(&to_node(&1, src, image, ip))
    |> Enum.into(%{})
  end

  defp to_node(1, src, image, ip) do
    {"node1",
     %{
       build: %{context: src},
       image: image,
       environment: %{
         "ARCHETHIC_CRYPTO_SEED" => "node1",
         "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => seeder(ip.(1 + 1)),
         "ARCHETHIC_STATIC_IP" => ip.(1 + 1),
         "ARCHETHIC_DB_HOST" => "scylladb1:9042"
       },
       volumes: [
         "#{Path.join([src, "/scripts/wait-for-tcp.sh"])}:/wait-for-tcp.sh:ro"
       ],
       networks: %{:net => %{ipv4_address: ip.(1 + 1)}},
       command: [
         "/wait-for-tcp.sh",
         "scylladb1:9042",
         "--timeout=0",
         "--strict",
         "--",
         "./bin/archethic_node",
         "foreground"
       ]
     }}
  end

  defp to_node(n, src, image, ip) do
    {"node#{n}",
     %{
       image: image,
       depends_on: ["node1"],
       environment: %{
         "ARCHETHIC_CRYPTO_SEED" => "node#{n}",
         "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => seeder(ip.(1 + 1)),
         "ARCHETHIC_STATIC_IP" => ip.(n + 1),
         "ARCHETHIC_DB_HOST" => "scylladb#{n}:9042"
       },
       networks: %{:net => %{ipv4_address: ip.(n + 1)}},
       volumes: [
         "#{Path.join([src, "/scripts/wait-for-tcp.sh"])}:/wait-for-tcp.sh:ro",
         "#{Path.join([src, "/scripts/wait-for-node.sh"])}:/wait-for-node.sh:ro"
       ],
       command: [
         "/wait-for-tcp.sh",
         "scylladb#{n}:9042",
         "--timeout=0",
         "--strict",
         "--",
         "/wait-for-node.sh",
         "http://node1:#{web_port()}/up",
         "./bin/archethic_node",
         "foreground"
       ]
     }}
  end

  defp pubkey(seed), do: seed |> Crypto.derive_keypair(0) |> elem(0) |> Base.encode16()

  defp seeder(addr), do: "#{addr}:#{p2p_port()}:#{pubkey("node1")}:tcp"
end
