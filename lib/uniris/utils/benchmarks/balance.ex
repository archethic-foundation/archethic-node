defmodule Uniris.Benchmark.Balance do
  @moduledoc """
  Benchmark balance
  """

  require Logger

  alias Uniris.Benchmark
  alias Uniris.Crypto
  alias Uniris.P2P.Message
  alias Uniris.P2P.Message.GetBalance
  alias Uniris.Utils
  alias Uniris.WebClient

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:uniris, Uniris.P2P.Endpoint)[:port]
    http = Application.get_env(:uniris, UnirisWeb.Endpoint)[:http][:port]
    {:ok, addr} = :inet.getaddr(to_charlist(host), :inet)

    {:ok, sock} = :socket.open(:inet, :stream, :tcp)
    :ok = :socket.connect(sock, %{family: :inet, port: port, addr: addr})

    {%{
       "P2P socket" => fn -> get_balance_p2p_socket(addr, port) end,
       "P2P gentcp" => fn -> get_balance_p2p_gentcp(addr, port) end,
       "P2P attach" => fn -> get_balance_p2p(sock) end,
       "WEB" => fn -> get_balance_web(host, http) end
     }, []}
  end

  @genesis Application.compile_env!(:uniris, Uniris.Bootstrap.NetworkInit)[:genesis_pools]
  @balance @genesis[:foundation][:amount]
  @address @genesis[:foundation][:public_key] |> Base.decode16!() |> Crypto.hash()
  @message %GetBalance{address: @address} |> Message.encode() |> Utils.wrap_binary()
  @msgdata <<byte_size(@message) + 4::32, 1::32, @message::binary>>

  defp get_balance_p2p_socket(addr, port) do
    {:ok, sock} = :socket.open(:inet, :stream, :tcp)
    :ok = :socket.connect(sock, %{family: :inet, port: port, addr: addr})
    :ok = :socket.send(sock, @msgdata)
    {:ok, <<_::32, _::32, data::binary>>} = :socket.recv(sock, 0, 1000)
    :ok = :socket.close(sock)

    {%Uniris.P2P.Message.Balance{nft: %{}, uco: @balance}, ""} = Message.decode(data)

    :ok
  end

  defp get_balance_p2p(sock) do
    :ok = :socket.send(sock, @msgdata)
    {:ok, <<_::32, _::32, data::binary>>} = :socket.recv(sock, 0, 1000)

    {%Uniris.P2P.Message.Balance{nft: %{}, uco: @balance}, ""} = Message.decode(data)

    :ok
  end

  defp get_balance_p2p_gentcp(addr, port) do
    {:ok, sock} = :gen_tcp.connect(addr, port, [:binary])
    :ok = :gen_tcp.send(sock, @msgdata)

    receive do
      {:tcp, ^sock, <<_::32, _::32, data::binary>>} ->
        :ok = :gen_tcp.close(sock)

        {%Uniris.P2P.Message.Balance{nft: %{}, uco: @balance}, ""} = Message.decode(data)

        :ok
    after
      1000 -> raise "timeout"
    end
  end

  @graphql """
  query {balance(address: "#{@address |> Base.encode16()}"){uco}}
  """

  defp get_balance_web(host, port) do
    {:ok, %{"data" => %{"balance" => %{"uco" => @balance}}}} =
      WebClient.with_connection(host, port, &WebClient.query(&1, @graphql))
  end
end
