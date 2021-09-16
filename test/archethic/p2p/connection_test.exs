defmodule ArchEthic.P2P.ConnectionTest do
  use ArchEthicCase, async: false

  alias ArchEthic.P2P.Connection

  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Message.Balance
  alias ArchEthic.P2P.Message.GetBalance

  alias __MODULE__.Reader

  import Mox

  describe "send_message/2" do
    test "should send data remotly and get response" do
      MockTransport
      |> expect(:read_from_socket, fn _, _, _ ->
        Reader.get_msg()
      end)
      |> expect(:read_from_socket, fn _, _, _ ->
        {:error, :closed}
      end)
      |> expect(:send_message, fn _, _ ->
        send(Reader, :msg)
        :ok
      end)
      |> expect(:close_socket, fn _ -> :ok end)

      {:ok, pid} =
        Connection.start_link(socket: make_ref(), transport: MockTransport, initiator?: true)

      address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      Reader.start_link()

      assert {:ok, %Balance{uco: 10.0}} =
               Connection.send_message(pid, %GetBalance{
                 address: address
               })

      Process.exit(pid, :normal)

      Process.sleep(200)
    end
  end

  defmodule Reader do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    def get_msg do
      GenServer.call(__MODULE__, :get_msg)
    end

    def init(_) do
      {:ok, %{}}
    end

    def handle_info(:msg, state = %{from: from}) do
      sender_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      GenServer.reply(
        from,
        {:ok,
         <<0::32, 0::8, sender_public_key::binary, Message.encode(%Balance{uco: 10.0})::binary>>}
      )

      {:noreply, state}
    end

    def handle_info(:msg, state), do: {:noreply, state}

    def handle_call(:get_msg, from, state) do
      {:noreply, Map.put(state, :from, from)}
    end
  end
end
