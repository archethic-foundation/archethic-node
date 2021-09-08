defmodule ArchEthic.Benchmark.Balance do
  @moduledoc """
  Benchmark balance
  """

  require Logger

  alias ArchEthic.Benchmark

  alias ArchEthic.Bootstrap.NetworkInit

  alias ArchEthic.P2P.Endpoint, as: P2PEndpoint
  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Message.Balance
  alias ArchEthic.P2P.Message.GetBalance

  alias ArchEthic.Utils

  alias ArchEthic.WebClient

  alias ArchEthicWeb.Endpoint, as: WebEndpoint

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, P2PEndpoint)[:port]
    http = Application.get_env(:archethic, WebEndpoint)[:http][:port]
    {:ok, addr} = :inet.getaddr(to_charlist(host), :inet)

    {:ok, sock} = :socket.open(:inet, :stream, :tcp)
    :ok = :socket.connect(sock, %{family: :inet, port: port, addr: addr})

    genesis_balance = get_genesis_balance()
    genesis_address = get_genesis_address()

    {%{
       "P2P socket" => fn _ ->
         get_balance_p2p_socket(addr, port, genesis_balance, genesis_address)
       end,
       "P2P gentcp" => fn _ ->
         get_balance_p2p_gentcp(addr, port, genesis_balance, genesis_address)
       end,
       "P2P attach" => fn _ -> get_balance_p2p(sock, genesis_balance, genesis_address) end,
       "WEB" => fn _ -> get_balance_web(host, http, genesis_balance, genesis_address) end
     },
     [
       before_scenario: fn _ -> get_vm_status(host, http) end,
       after_scenario: fn before ->
         now = get_vm_status(host, http)

         [{"vm_system_counts_process_count", 20}]
         |> Enum.each(fn {metric, delta} ->
           Logger.info("Checking #{metric} #{before[metric]} vs #{now[metric]}")

           if before[metric] + delta - now[metric] < 0 do
             raise RuntimeError, message: "leak of #{metric} is detected"
           end
         end)
       end
     ]}
  end

  defp get_vm_status(host, port) do
    {:ok, data} = WebClient.with_connection(host, port, &WebClient.request(&1, "GET", "/metrics"))

    data
    |> :erlang.iolist_to_binary()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "vm_"))
    |> Enum.map(fn kv ->
      [k, v] = String.split(kv)
      {k, v |> Integer.parse() |> elem(0)}
    end)
    |> Enum.into(%{})
  end

  defp get_genesis_balance do
    get_genesis_pools()
    |> Enum.at(0)
    |> Map.get(:amount)
  end

  defp get_genesis_address do
    get_genesis_pools()
    |> Enum.at(0)
    |> Map.get(:address)
  end

  defp get_genesis_pools do
    :archethic
    |> Application.get_env(:archethic, NetworkInit)
    |> Keyword.fetch!(:genesis_pools)
  end

  defp message_data(address) do
    message_bin =
      %GetBalance{address: address}
      |> Message.encode()
      |> Utils.wrap_binary()

    <<byte_size(message_bin) + 4::32, 1::32, message_bin::binary>>
  end

  defp get_balance_p2p_socket(addr, port, expected_balance, address) do
    {:ok, sock} = :socket.open(:inet, :stream, :tcp)
    :ok = :socket.connect(sock, %{family: :inet, port: port, addr: addr})
    :ok = :socket.send(sock, message_data(address))
    {:ok, <<_::32, _::32, data::binary>>} = :socket.recv(sock, 0, 1000)
    :ok = :socket.close(sock)

    {%Balance{nft: %{}, uco: ^expected_balance}, ""} = Message.decode(data)

    :ok
  end

  defp get_balance_p2p(sock, expected_balance, address) do
    :ok = :socket.send(sock, message_data(address))
    {:ok, <<_::32, _::32, data::binary>>} = :socket.recv(sock, 0, 1000)

    {%Balance{nft: %{}, uco: ^expected_balance}, ""} = Message.decode(data)

    :ok
  end

  defp get_balance_p2p_gentcp(addr, port, expected_balance, address) do
    {:ok, sock} = :gen_tcp.connect(addr, port, [:binary])
    :ok = :gen_tcp.send(sock, message_data(address))

    receive do
      {:tcp, ^sock, <<_::32, _::32, data::binary>>} ->
        :ok = :gen_tcp.close(sock)

        {%Balance{nft: %{}, uco: ^expected_balance}, ""} = Message.decode(data)

        :ok
    after
      1000 -> raise "timeout"
    end
  end

  defp get_balance_web(host, port, expected_balance, address) do
    query = """
    query { 
      balance(address: "#{Base.encode16(address)}") {
        uco
      }
    }
    """

    {:ok, %{"data" => %{"balance" => %{"uco" => ^expected_balance}}}} =
      WebClient.with_connection(host, port, &WebClient.query(&1, query))
  end
end
