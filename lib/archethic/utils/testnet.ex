defmodule Archethic.Utils.Testnet do
  @moduledoc """
  Archethic Testnet Generator
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
        {:ok, %Subnet{address: {192, 168, 0, 1}, mask: 24}}

        iex> "2001:db8::/64" |> Subnet.parse()
        {:ok, %Subnet{address: {8193, 3512, 0, 0, 0, 0, 0, 0}, mask: 64}}

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
        %Subnet{address: {192, 168, 0, 1}, mask: 24}

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

  alias Archethic.Crypto

  defp p2p_port, do: 30_002
  defp web_port, do: 40_000

  @validator_1_ip 220
  @validator_2_ip 230
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
        "    - 1.2.3.2:40000\\n" <>
        "    - 1.2.3.3:40000\\n" <>
        "    - 1.2.3.4:40000\\n\\n"},
      {"docker-compose.json", %{
        version: "3.9",
          networks: %{:net => %{ipam: %{config: [%{subnet: "1.2.3.0/24"}], driver: :default}}},
          services: %{
            "node1" => %{
              build:  %{context: "c"},
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "node1",
                "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => "1.2.3.2:30002:00011D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.2",
                "ARCHETHIC_NETWORKING_IMPL" => "STATIC",
                "ARCHETHIC_NETWORKING_PORT_FORWARDING" => "false",
                "ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS" => "software",
                "ARCHETHIC_LOGGER_LEVEL" => "debug",
                "ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL" => "*/10 * * * * *",
                "ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL" => "0 * * * * *",
                "ARCHETHIC_ORACLE_CHAIN_POLLING_INTERVAL" => "*/10 * * * * *",
                "ARCHETHIC_ORACLE_CHAIN_SUMMARY_INTERVAL" => "0 * * * * *",
                "ARCHETHIC_SHARED_SECRETS_RENEWAL_SCHEDULER_INTERVAL" => "40 * * * * * *",
                "ARCHETHIC_SHARED_SECRETS_APPLICATION_INTERVAL" => "0 * * * * * *",
                "ARCHETHIC_SELF_REPAIR_SCHEDULER_INTRERVAL" => "5 * * * * * *",
                "ARCHETHIC_NODE_IP_VALIDATION" => "false",
                "ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL" => "SOFTWARE",
                "ARCHETHIC_CRYPTO_ROOT_CA_SOFTWARE_PUBKEY" => "",
                "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY" => "",
                "ARCHETHIC_NETWORK_TYPE" => "testnet",
                "ARCHETHIC_THROTTLE_IP_AND_PATH" => 999999,
                "ARCHETHIC_THROTTLE_IP_HIGH" => 999999,
                "ARCHETHIC_THROTTLE_IP_LOW" => 999999
              },
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.2"}},
              command: [
                "./bin/archethic_node",
                "foreground"
              ],
              volumes: [
                "c/scripts/wait-for-tcp.sh:/wait-for-tcp.sh:ro"
              ]
            },
            "node2" => %{
              depends_on: ["node1"],
              build:  %{context: "c"},
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "node2",
                "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => "1.2.3.2:30002:00011D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.3",
                "ARCHETHIC_NETWORKING_IMPL" => "STATIC",
                "ARCHETHIC_NETWORKING_PORT_FORWARDING" => "false",
                "ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS" => "software",
                "ARCHETHIC_LOGGER_LEVEL" => "debug",
                "ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL" => "*/10 * * * * *",
                "ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL" => "0 * * * * *",
                "ARCHETHIC_ORACLE_CHAIN_POLLING_INTERVAL" => "*/10 * * * * *",
                "ARCHETHIC_ORACLE_CHAIN_SUMMARY_INTERVAL" => "0 * * * * *",
                "ARCHETHIC_SHARED_SECRETS_RENEWAL_SCHEDULER_INTERVAL" => "40 * * * * * *",
                "ARCHETHIC_SHARED_SECRETS_APPLICATION_INTERVAL" => "0 * * * * * *",
                "ARCHETHIC_SELF_REPAIR_SCHEDULER_INTRERVAL" => "5 * * * * * *",
                "ARCHETHIC_NODE_IP_VALIDATION" => "false",
                "ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL" => "SOFTWARE",
                "ARCHETHIC_CRYPTO_ROOT_CA_SOFTWARE_PUBKEY" => "",
                "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY" => "",
                "ARCHETHIC_NETWORK_TYPE" => "testnet",
                "ARCHETHIC_THROTTLE_IP_AND_PATH" => 999999,
                "ARCHETHIC_THROTTLE_IP_HIGH" => 999999,
                "ARCHETHIC_THROTTLE_IP_LOW" => 999999
              },
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.3"}},
              volumes: [
                "c/scripts/wait-for-tcp.sh:/wait-for-tcp.sh:ro",
                "c/scripts/wait-for-node.sh:/wait-for-node.sh:ro"
              ],
              command: [
                "/wait-for-tcp.sh",
                "--host=1.2.3.2",
                "--port=30002",
                "--timeout=0",
                "--strict",
                "--",
                "/wait-for-node.sh",
                "http://1.2.3.2:40000/up",
                "./bin/archethic_node",
                "foreground"
              ]
            },
            "node3" => %{
              depends_on: ["node1"],
              build:  %{context: "c"},
              environment: %{
                "ARCHETHIC_CRYPTO_SEED" => "node3",
                "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => "1.2.3.2:30002:00011D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp",
                "ARCHETHIC_STATIC_IP" => "1.2.3.4",
                "ARCHETHIC_NETWORKING_IMPL" => "STATIC",
                "ARCHETHIC_NETWORKING_PORT_FORWARDING" => "false",
                "ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS" => "software",
                "ARCHETHIC_LOGGER_LEVEL" => "debug",
                "ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL" => "*/10 * * * * *",
                "ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL" => "0 * * * * *",
                "ARCHETHIC_ORACLE_CHAIN_POLLING_INTERVAL" => "*/10 * * * * *",
                "ARCHETHIC_ORACLE_CHAIN_SUMMARY_INTERVAL" => "0 * * * * *",
                "ARCHETHIC_SHARED_SECRETS_RENEWAL_SCHEDULER_INTERVAL" => "40 * * * * * *",
                "ARCHETHIC_SHARED_SECRETS_APPLICATION_INTERVAL" => "0 * * * * * *",
                "ARCHETHIC_SELF_REPAIR_SCHEDULER_INTRERVAL" => "5 * * * * * *",
                "ARCHETHIC_NODE_IP_VALIDATION" => "false",
                "ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL" => "SOFTWARE",
                "ARCHETHIC_CRYPTO_ROOT_CA_SOFTWARE_PUBKEY" => "",
                "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY" => "",
                "ARCHETHIC_NETWORK_TYPE" => "testnet",
                "ARCHETHIC_THROTTLE_IP_AND_PATH" => 999999,
                "ARCHETHIC_THROTTLE_IP_HIGH" => 999999,
                "ARCHETHIC_THROTTLE_IP_LOW" => 999999
              },
              image: "i",
              networks: %{:net => %{ipv4_address: "1.2.3.4"}},
              volumes: [
                "c/scripts/wait-for-tcp.sh:/wait-for-tcp.sh:ro",
                "c/scripts/wait-for-node.sh:/wait-for-node.sh:ro"
              ],
              command: [
                "/wait-for-tcp.sh",
                "--host=1.2.3.2",
                "--port=30002",
                "--timeout=0",
                "--strict",
                "--",
                "/wait-for-node.sh",
                "http://1.2.3.2:40000/up",
                "./bin/archethic_node",
                "foreground"
              ]
            },
            "collector" => %{
              image: "prom/prometheus",
              networks: %{:net => %{ipv4_address: "1.2.3.#{@collector_ip}"}},
              volumes: [".prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
            },
            "validator_1" => %{
              image: "i",
              environment: %{
                "ARCHETHIC_MUT_DIR" => "/opt/data"
              },
              command: ["./bin/archethic_node", "validate", "1.2.3.2", "1.2.3.3", "1.2.3.4", "--phase=1"],
              volumes: [
                "./validator_data/:/opt/data"
              ],
              networks: %{:net => %{ipv4_address: "1.2.3.#{@validator_1_ip}"}},
            },
             "validator_2" => %{
              image: "i",
              environment: %{
                "ARCHETHIC_MUT_DIR" => "/opt/data"
              },
              command: ["./bin/archethic_node", "validate", "1.2.3.2", "1.2.3.3", "1.2.3.4", "--phase=2"],
              volumes: [
                "./validator_data/:/opt/data"
              ],
              networks: %{:net => %{ipv4_address: "1.2.3.#{@validator_2_ip}"}},
              profiles: ["validate_2"]
            },
            "bench" => %{
              image: "i",
              environment: %{
                "ARCHETHIC_MUT_DIR" => "/opt/data"
              },
              command: ["./bin/archethic_node", "regression_test", "--bench", "1.2.3.2", "1.2.3.3", "1.2.3.4"],
              volumes: [
                "./bench_data/:/opt/data"
              ],
              networks: %{ :net => %{ipv4_address: "1.2.3.#{@bench_ip}"}}
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

    uninodes =
      Enum.map(services, fn {_, %{environment: %{"ARCHETHIC_STATIC_IP" => ip}}} -> ip end)

    networks = %{:net => %{ipam: %{driver: :default, config: [%{subnet: subnet}]}}}

    services =
      services
      |> Map.put("collector", %{
        image: "prom/prometheus",
        networks: %{:net => %{ipv4_address: ip.(@collector_ip)}},
        volumes: [".prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
      })
      |> Map.put("validator_1", %{
        image: image,
        environment: %{
          "ARCHETHIC_MUT_DIR" => "/opt/data"
        },
        command: ["./bin/archethic_node", "validate" | uninodes] ++ ["--phase=1"],
        volumes: [
          "./validator_data/:/opt/data"
        ],
        networks: %{:net => %{ipv4_address: ip.(@validator_1_ip)}}
      })
      |> Map.put("validator_2", %{
        image: image,
        environment: %{
          "ARCHETHIC_MUT_DIR" => "/opt/data"
        },
        command: ["./bin/archethic_node", "validate" | uninodes] ++ ["--phase=2"],
        volumes: [
          "./validator_data/:/opt/data"
        ],
        profiles: ["validate_2"],
        networks: %{:net => %{ipv4_address: ip.(@validator_2_ip)}}
      })
      |> Map.put("bench", %{
        image: image,
        environment: %{
          "ARCHETHIC_MUT_DIR" => "/opt/data"
        },
        command: ["./bin/archethic_node", "regression_test", "--bench" | uninodes],
        volumes: [
          "./bench_data/:/opt/data"
        ],
        networks: %{:net => %{ipv4_address: ip.(@bench_ip)}}
      })

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
    node_1_ip_address = ip.(1 + 1)

    {"node1",
     %{
       build: %{context: src},
       image: image,
       environment: %{
         "ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL" => "SOFTWARE",
         "ARCHETHIC_CRYPTO_SEED" => "node1",
         "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => seeder(node_1_ip_address),
         "ARCHETHIC_STATIC_IP" => ip.(1 + 1),
         "ARCHETHIC_NETWORKING_IMPL" => "STATIC",
         "ARCHETHIC_NETWORKING_PORT_FORWARDING" => "false",
         "ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS" => "software",
         "ARCHETHIC_LOGGER_LEVEL" => "debug",
         "ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL" => "*/10 * * * * *",
         "ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL" => "0 * * * * *",
         "ARCHETHIC_ORACLE_CHAIN_POLLING_INTERVAL" => "*/10 * * * * *",
         "ARCHETHIC_ORACLE_CHAIN_SUMMARY_INTERVAL" => "0 * * * * *",
         "ARCHETHIC_SHARED_SECRETS_RENEWAL_SCHEDULER_INTERVAL" => "40 * * * * * *",
         "ARCHETHIC_SHARED_SECRETS_APPLICATION_INTERVAL" => "0 * * * * * *",
         "ARCHETHIC_SELF_REPAIR_SCHEDULER_INTRERVAL" => "5 * * * * * *",
         "ARCHETHIC_NODE_IP_VALIDATION" => "false",
         "ARCHETHIC_CRYPTO_ROOT_CA_SOFTWARE_PUBKEY" => "",
         "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY" => "",
         "ARCHETHIC_NETWORK_TYPE" => "testnet",
         "ARCHETHIC_THROTTLE_IP_HIGH" => 999_999,
         "ARCHETHIC_THROTTLE_IP_LOW" => 999_999,
         "ARCHETHIC_THROTTLE_IP_AND_PATH" => 999_999
       },
       volumes: [
         "#{Path.join([src, "/scripts/wait-for-tcp.sh"])}:/wait-for-tcp.sh:ro"
       ],
       networks: %{:net => %{ipv4_address: ip.(1 + 1)}},
       command: [
         "./bin/archethic_node",
         "foreground"
       ]
     }}
  end

  defp to_node(n, src, image, ip) do
    node_1_ip_address = ip.(1 + 1)
    ip_address = ip.(n + 1)

    {"node#{n}",
     %{
       build: %{context: src},
       image: image,
       depends_on: ["node1"],
       environment: %{
         "ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL" => "SOFTWARE",
         "ARCHETHIC_CRYPTO_SEED" => "node#{n}",
         "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS" => seeder(node_1_ip_address),
         "ARCHETHIC_STATIC_IP" => ip_address,
         "ARCHETHIC_NETWORKING_IMPL" => "STATIC",
         "ARCHETHIC_NETWORKING_PORT_FORWARDING" => "false",
         "ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS" => "software",
         "ARCHETHIC_LOGGER_LEVEL" => "debug",
         "ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL" => "*/10 * * * * *",
         "ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL" => "0 * * * * *",
         "ARCHETHIC_ORACLE_CHAIN_POLLING_INTERVAL" => "*/10 * * * * *",
         "ARCHETHIC_ORACLE_CHAIN_SUMMARY_INTERVAL" => "0 * * * * *",
         "ARCHETHIC_SHARED_SECRETS_RENEWAL_SCHEDULER_INTERVAL" => "40 * * * * * *",
         "ARCHETHIC_SHARED_SECRETS_APPLICATION_INTERVAL" => "0 * * * * * *",
         "ARCHETHIC_SELF_REPAIR_SCHEDULER_INTRERVAL" => "5 * * * * * *",
         "ARCHETHIC_NODE_IP_VALIDATION" => "false",
         "ARCHETHIC_CRYPTO_ROOT_CA_SOFTWARE_PUBKEY" => "",
         "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY" => "",
         "ARCHETHIC_NETWORK_TYPE" => "testnet",
         "ARCHETHIC_THROTTLE_IP_HIGH" => 999_999,
         "ARCHETHIC_THROTTLE_IP_LOW" => 999_999,
         "ARCHETHIC_THROTTLE_IP_AND_PATH" => 999_999
       },
       networks: %{:net => %{ipv4_address: ip_address}},
       volumes: [
         "#{Path.join([src, "/scripts/wait-for-tcp.sh"])}:/wait-for-tcp.sh:ro",
         "#{Path.join([src, "/scripts/wait-for-node.sh"])}:/wait-for-node.sh:ro"
       ],
       command: [
         "/wait-for-tcp.sh",
         "--host=#{node_1_ip_address}",
         "--port=#{p2p_port()}",
         "--timeout=0",
         "--strict",
         "--",
         "/wait-for-node.sh",
         "http://#{node_1_ip_address}:#{web_port()}/up",
         "./bin/archethic_node",
         "foreground"
       ]
     }}
  end

  defp pubkey(seed), do: seed |> Crypto.derive_keypair(0) |> elem(0) |> Base.encode16()

  defp seeder(addr), do: "#{addr}:#{p2p_port()}:#{pubkey("node1")}:tcp"
end
