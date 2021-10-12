defmodule ArchEthic.Utils.Regression.Benchmark.P2PMessage do
  @moduledoc """
  Benchmark some P2P messages to ensure consistent latency
  and avoiding exhausting of the system (nb of process should remain constant)
  """

  require Logger

  alias ArchEthic.Bootstrap.NetworkInit

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.TransactionList

  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils
  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.WebClient

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthic.P2P.Endpoint)[:port]
    http = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]
    {:ok, addr} = :inet.getaddr(to_charlist(host), :inet)

    {%{
       "GetTransaction" => fn _ -> get_transaction(addr, port) end,
       "GetTransactionChain" => fn _ -> get_transaction_chain(addr, port) end
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

  defp get_genesis_address do
    Application.get_env(:archethic, NetworkInit)
    |> Keyword.fetch!(:genesis_seed)
    |> Crypto.derive_keypair(1)
    |> elem(0)
    |> Crypto.hash()
  end

  defp get_transaction(addr, port) do
    {:ok, socket} = connect(addr, port)
    :ok = send_msg(socket, %GetTransaction{address: get_genesis_address()})
    {:ok, %Transaction{}} = recv(socket)
  end

  defp get_transaction_chain(addr, port) do
    {:ok, socket} = connect(addr, port)
    :ok = send_msg(socket, %GetTransactionChain{address: get_genesis_address()})
    {:ok, %TransactionList{transactions: _}} = recv(socket)
  end

  defp connect(addr, port) do
    :gen_tcp.connect(addr, port, [:binary, packet: 4, active: false])
  end

  defp send_msg(socket, message) do
    msg_binary =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    case :gen_tcp.send(
           socket,
           <<1::32, 0::8, 0::8, 0::8, :crypto.strong_rand_bytes(32)::binary, msg_binary::binary>>
         ) do
      :ok ->
        :ok

      e ->
        :gen_tcp.close(socket)
        e
    end
  end

  defp recv(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, <<_::32, 0::8, _::binary-size(34), data::binary>>} ->
        {msg, _} = Message.decode(data)
        {:ok, msg}

      e ->
        :gen_tcp.close(socket)
        e
    end
  end
end
