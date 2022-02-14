defmodule ArchEthic.Utils.Regression.Benchmark.P2PMessage do
  @moduledoc """
  Benchmark some P2P messages to ensure consistent latency
  and avoiding exhausting of the system (nb of process should remain constant)
  """

  require Logger

  alias ArchEthic.Bootstrap.NetworkInit

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.Message.Balance
  alias ArchEthic.P2P.Message.GetBalance
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.TransactionList

  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.WebClient

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthic.P2P.Listener)[:port]
    http = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]
    {:ok, addr} = :inet.getaddr(to_charlist(host), :inet)

    {public_key, private_key} =
      Crypto.generate_deterministic_keypair(:crypto.strong_rand_bytes(32), :secp256r1)

    {:ok, conn_pid} =
      __MODULE__.Connection.start_link(
        addr: addr,
        port: port,
        public_key: public_key,
        private_key: private_key
      )

    {%{
       "GetTransaction" => fn _ ->
         %Transaction{} =
           __MODULE__.Connection.send_message(conn_pid, %GetTransaction{
             address: get_genesis_address()
           })
       end,
       "GetTransactionChain" => fn _ ->
         %TransactionList{} =
           __MODULE__.Connection.send_message(conn_pid, %GetTransactionChain{
             address: get_genesis_address()
           })
       end,
       "GetBalance" => fn _ ->
         %Balance{} =
           __MODULE__.Connection.send_message(conn_pid, %GetBalance{
             address: get_genesis_address()
           })
       end
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
    |> Crypto.derive_address()
  end

  defmodule Connection do
    @moduledoc false
    alias ArchEthic.Crypto

    alias ArchEthic.P2P.Message
    alias ArchEthic.P2P.MessageEnvelop

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    def send_message(pid, message) do
      GenServer.call(pid, {:send_message, message})
    end

    def init(arg) do
      addr = Keyword.get(arg, :addr)
      port = Keyword.get(arg, :port)
      public_key = Keyword.get(arg, :public_key)
      private_key = Keyword.get(arg, :private_key)

      {:ok, socket} = :gen_tcp.connect(addr, port, [:binary, active: true, packet: 4])

      {:ok,
       %{
         socket: socket,
         messages: %{},
         request_id: 0,
         public_key: public_key,
         private_key: private_key
       }}
    end

    def handle_call(
          {:send_message, msg},
          from,
          state = %{socket: socket, public_key: public_key, request_id: request_id}
        ) do
      envelop =
        %MessageEnvelop{
          message: msg,
          message_id: request_id,
          sender_public_key: public_key
        }
        |> MessageEnvelop.encode()

      :gen_tcp.send(socket, envelop)

      new_state =
        state
        |> Map.update!(:request_id, &(&1 + 1))
        |> Map.update!(:messages, &Map.put(&1, request_id, from))

      {:noreply, new_state}
    end

    def handle_info({:tcp, _, data}, state = %{private_key: private_key, messages: messages}) do
      {msg_id, encrypted_message} = MessageEnvelop.decode_raw_message(data)

      msg =
        encrypted_message
        |> Crypto.ec_decrypt!(private_key)
        |> Message.decode()
        |> elem(0)

      case Map.pop(messages, msg_id) do
        {nil, _} ->
          {:noreply, state}

        {from, messages} ->
          GenServer.reply(from, msg)
          {:noreply, %{state | messages: messages}}
      end
    end
  end
end
