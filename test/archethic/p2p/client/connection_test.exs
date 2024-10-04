defmodule Archethic.P2P.Client.ConnectionTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P.Client.Connection
  alias Archethic.P2P.Client.ConnectionSupervisor
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.MessageEnvelop

  alias Archethic.TransactionFactory
  alias Archethic.TransactionChain.Transaction

  alias Archethic.Utils

  @heartbeat_interval Keyword.get(
                        Application.compile_env(:archethic, Connection, []),
                        :heartbeat_interval,
                        10_000
                      )

  test "start_link/1 should open a socket and a connection worker and initialize the backlog and lookup tables" do
    {:ok, pid} =
      Connection.start_link(
        transport: __MODULE__.MockTransport,
        ip: {127, 0, 0, 1},
        port: 3000,
        node_public_key: "key1"
      )

    Process.sleep(10)

    assert {{:connected, _socket}, %{request_id: 0, messages: %{}}} = :sys.get_state(pid)
  end

  test "start_link/1 should acknowledge when connection is successful" do
    me = self()

    {:ok, pid} =
      Connection.start_link(
        transport: __MODULE__.MockTransport,
        ip: {127, 0, 0, 1},
        port: 3000,
        node_public_key: "key1",
        from: me
      )

    assert {:initializing, _} = :sys.get_state(pid)

    Process.sleep(10)

    assert {{:connected, _socket}, %{request_id: 0, messages: %{}}} = :sys.get_state(pid)
    assert_received :connected
  end

  describe "send_message/3" do
    test "should send the message and enqueue the request" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransport,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      spawn(fn ->
        Connection.send_message(Crypto.first_node_public_key(), %GetTransaction{
          address: ArchethicCase.random_address()
        })
      end)

      Process.sleep(50)

      assert {{:connected, _socket},
              %{
                messages: %{0 => _},
                request_id: 1
              }} = :sys.get_state(pid)
    end

    test "should get an error, :closed when trying to reach an unreachable node" do
      defmodule MockTransportUnreachable do
        alias Archethic.P2P.Client.Transport

        @behaviour Transport

        def handle_connect(_ip, _port) do
          {:error, :timeout}
        end

        def handle_close(_socket) do
          :ok
        end

        def handle_send(_socket, <<0::32, _rest::bitstring>>), do: :ok

        def handle_message({_, _, _}), do: {:error, :closed}
      end

      {:ok, _} =
        Connection.start_link(
          transport: MockTransportUnreachable,
          ip: {127, 0, 0, 2},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      assert {:error, :closed} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()}
               )
    end

    test "reconnection should be asynchronous" do
      defmodule MockTransportConnectionTimeout do
        alias Archethic.P2P.Client.Transport

        @behaviour Transport

        def handle_connect({127, 0, 0, 1}, _port) do
          {:error, :timeout}
        end

        def handle_connect({127, 0, 0, 2}, _port) do
          Process.sleep(100_000)
          {:error, :timeout}
        end

        def handle_close(_socket) do
          :ok
        end

        def handle_send(_socket, <<0::32, _rest::bitstring>>), do: :ok

        def handle_message({_, _, _}), do: {:error, :closed}
      end

      {:ok, pid} =
        Connection.start_link(
          transport: MockTransportConnectionTimeout,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      :sys.replace_state(pid, fn {state, data} ->
        {state, Map.put(data, :ip, {127, 0, 0, 2})}
      end)

      # 500ms to wait for the 1st reconnect attempt
      Process.sleep(550)

      time = System.monotonic_time(:millisecond)

      assert {:error, :closed} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()},
                 200
               )

      # ensure there was no delay
      time2 = System.monotonic_time(:millisecond)
      assert time2 - time < 100
    end

    test "should be in :connected state after reconnection" do
      defmodule MockTransportReconnectionSuccess do
        alias Archethic.P2P.Client.Transport

        @behaviour Transport

        def handle_connect({127, 0, 0, 1}, _port) do
          {:error, :timeout}
        end

        def handle_connect({127, 0, 0, 2}, _port) do
          {:ok, make_ref()}
        end

        def handle_close(_socket) do
          :ok
        end

        def handle_send(_socket, _), do: :ok

        def handle_message({_, _, _}), do: {:error, :closed}
      end

      {:ok, pid} =
        Connection.start_link(
          transport: MockTransportReconnectionSuccess,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      :sys.replace_state(pid, fn {state, data} ->
        {state, Map.put(data, :ip, {127, 0, 0, 2})}
      end)

      # 500ms to wait for the 1st reconnect attempt
      Process.sleep(550)

      assert {{:connected, _socket}, _} = :sys.get_state(pid)
    end

    test "should get an error when the timeout is reached" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransport,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      assert {:error, :timeout} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()},
                 10
               )

      assert {_, %{messages: %{}}} = :sys.get_state(pid)
    end

    test "should receive the response after sending the request" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransport,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      me = self()

      spawn(fn ->
        {:ok, %Transaction{}} =
          Connection.send_message(
            Crypto.first_node_public_key(),
            %GetTransaction{address: ArchethicCase.random_address()}
          )

        send(me, :done)
      end)

      Process.sleep(100)

      tx = TransactionFactory.create_valid_transaction([], type: :node, seed: "node1")

      signature =
        tx
        |> Message.encode()
        |> Utils.wrap_binary()
        |> Crypto.sign_with_first_node_key()

      msg_envelop =
        %MessageEnvelop{
          message: tx,
          message_id: 0,
          sender_public_key: Crypto.first_node_public_key(),
          signature: signature
        }
        |> MessageEnvelop.encode(Crypto.first_node_public_key())

      send(pid, {__MODULE__.MockTransport, make_ref(), msg_envelop})

      assert_receive :done, 3_000

      assert {{:connected, _socket},
              %{
                messages: %{}
              }} = :sys.get_state(pid)
    end

    test "notify when the message cannot be transmitted" do
      defmodule MockTransportDisconnected do
        alias Archethic.P2P.Client.Transport

        @behaviour Transport

        def handle_connect(_ip, _port) do
          {:ok, make_ref()}
        end

        def handle_close(_socket) do
          :ok
        end

        def handle_send(_socket, <<0::32, _rest::bitstring>>), do: :ok
        def handle_send(_socket, <<_::32, _rest::bitstring>>), do: {:error, :closed}

        def handle_message({_, _, data}), do: {:ok, data}
      end

      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransportDisconnected,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      spawn(fn ->
        {:ok, %Transaction{}} =
          Connection.send_message(
            Crypto.first_node_public_key(),
            %GetTransaction{address: ArchethicCase.random_address()}
          )
      end)

      Process.sleep(10)

      tx = TransactionFactory.create_valid_transaction([], type: :node, seed: "node1")

      signature =
        tx
        |> Message.encode()
        |> Utils.wrap_binary()
        |> Crypto.sign_with_first_node_key()

      msg_envelop =
        %MessageEnvelop{
          message: tx,
          message_id: 0,
          sender_public_key: Crypto.first_node_public_key(),
          signature: signature
        }
        |> MessageEnvelop.encode(Crypto.first_node_public_key())

      send(pid, {__MODULE__.MockTransportDisconnected, make_ref(), msg_envelop})

      assert {:error, :closed} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()}
               )
    end

    test "notify when the node is disconnected" do
      defmodule MockTransportDisconnected2 do
        alias Archethic.P2P.Client.Transport

        @behaviour Transport

        def handle_connect(_ip, _port) do
          case :persistent_term.get(:disconnected, false) do
            false ->
              {:ok, make_ref()}

            true ->
              {:error, :closed}
          end
        end

        def handle_close(_socket) do
          :ok
        end

        def handle_send(_socket, <<0::32, _rest::bitstring>>), do: :ok

        def handle_send(_socket, <<_::32, _rest::bitstring>>) do
          :persistent_term.put(:disconnected, true)
          {:error, :closed}
        end

        def handle_message({_, _, data}), do: {:ok, data}
      end

      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransportDisconnected2,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      spawn(fn ->
        {:ok, %Transaction{}} =
          Connection.send_message(
            Crypto.first_node_public_key(),
            %GetTransaction{address: ArchethicCase.random_address()}
          )
      end)

      Process.sleep(10)

      tx = TransactionFactory.create_valid_transaction([], type: :node, seed: "node1")

      signature =
        tx
        |> Message.encode()
        |> Utils.wrap_binary()
        |> Crypto.sign_with_first_node_key()

      msg_envelop =
        %MessageEnvelop{
          message: tx,
          message_id: 0,
          sender_public_key: Crypto.first_node_public_key(),
          signature: signature
        }
        |> MessageEnvelop.encode(Crypto.first_node_public_key())

      send(pid, {__MODULE__.MockTransportDisconnected2, make_ref(), msg_envelop})

      assert {:error, :closed} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()}
               )

      assert {:error, :closed} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()}
               )
    end
  end

  describe "availability_timer" do
    test "should start when node connect" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransport,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: "key1"
        )

      Process.sleep(10)

      assert {{:connected, _socket}, %{availability_timer: {start, 0}}} = :sys.get_state(pid)
      assert start != nil
    end

    test "should stop and calculate time when the timeout is reached" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransport,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      assert {:error, :timeout} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()},
                 1000
               )

      Process.sleep(10)

      assert {_, %{availability_timer: {nil, 1}}} = :sys.get_state(pid)

      # restart timer simulating a reconnection
      send(pid, :start_timer)

      assert {_, %{availability_timer: {start, 1}}} = :sys.get_state(pid)
      assert start != nil

      assert {:error, :timeout} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()},
                 1000
               )

      Process.sleep(10)

      assert {_, %{availability_timer: {nil, 2}}} = :sys.get_state(pid)
    end

    test "should stop when node disconnect" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransportClosed,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      Process.sleep(10)

      assert {{:connected, _socket}, %{availability_timer: {start, 0}}} = :sys.get_state(pid)
      assert start != nil

      tx = TransactionFactory.create_valid_transaction([], type: :node, seed: "node1")

      signature =
        tx
        |> Message.encode()
        |> Utils.wrap_binary()
        |> Crypto.sign_with_first_node_key()

      msg_envelop =
        %MessageEnvelop{
          message: tx,
          message_id: 0,
          sender_public_key: Crypto.first_node_public_key(),
          signature: signature
        }
        |> MessageEnvelop.encode(Crypto.first_node_public_key())

      send(pid, {__MODULE__.MockTransportClosed, make_ref(), msg_envelop})

      Process.sleep(10)

      assert {_, %{availability_timer: {nil, 0}}} = :sys.get_state(pid)
    end
  end

  describe "get_availability_timer" do
    test "should return time value and reset timer" do
      {:ok, pid} =
        Connection.start_link(
          transport: __MODULE__.MockTransport,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      assert {:error, :timeout} =
               Connection.send_message(
                 Crypto.first_node_public_key(),
                 %GetTransaction{address: ArchethicCase.random_address()},
                 1000
               )

      Process.sleep(10)

      assert {_, %{availability_timer: {nil, 1}}} = :sys.get_state(pid)

      assert 1 == Connection.get_availability_timer(Crypto.first_node_public_key(), true)

      assert {_, %{availability_timer: {nil, 0}}} = :sys.get_state(pid)

      # restart timer simulating a reconnection
      send(pid, :start_timer)

      assert {_, %{availability_timer: {start, 0}}} = :sys.get_state(pid)

      assert 0 == Connection.get_availability_timer(Crypto.first_node_public_key(), false)

      assert {_, %{availability_timer: {^start, 0}}} = :sys.get_state(pid)
    end
  end

  describe "connected?" do
    test "shoud return true when node is connected and false when disconnected" do
      node_key = Crypto.first_node_public_key()

      {:ok, pid} =
        ConnectionSupervisor.add_connection(
          transport: __MODULE__.MockTransportClosed,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: node_key
        )

      Process.sleep(10)

      assert Connection.connected?(node_key)

      assert {:error, :timeout} =
               Connection.send_message(
                 node_key,
                 %GetTransaction{address: ArchethicCase.random_address()},
                 10
               )

      Process.sleep(10)

      refute Connection.connected?(node_key)

      ConnectionSupervisor.cancel_connection(pid)
    end
  end

  describe "Stale detection" do
    test "should change state to disconnected once a few heartbeats are missed" do
      defmodule MockTransportStale do
        alias Archethic.P2P.Client.Transport

        @behaviour Transport

        def handle_connect({127, 0, 0, 1}, _port) do
          conn_count = :persistent_term.get(:conn_count, 0)
          :persistent_term.put(:conn_count, conn_count + 1)

          if conn_count == 0 do
            {:ok, make_ref()}
          else
            {:error, :timeout}
          end
        end

        def handle_close(_socket) do
          :persistent_term.put(:transport_closed, true)
          :ok
        end

        def handle_send(_socket, "hb") do
          hb_count = :persistent_term.get(:hb_count, 0)
          :persistent_term.put(:hb_count, hb_count + 1)

          # become stale after 5 hbs
          if hb_count <= 5 do
            send(self(), {:tcp, make_ref(), "hb"})
          end

          :ok
        end

        def handle_send(_socket, _), do: :ok

        def handle_message({_, _, data}), do: {:ok, data}
      end

      {:ok, pid} =
        Connection.start_link(
          transport: MockTransportStale,
          ip: {127, 0, 0, 1},
          port: 3000,
          node_public_key: Crypto.first_node_public_key()
        )

      Process.sleep(@heartbeat_interval * 5)
      assert {{:connected, _}, _} = :sys.get_state(pid)

      Process.sleep(@heartbeat_interval * 5)
      assert {:disconnected, _} = :sys.get_state(pid)

      assert :persistent_term.get(:transport_closed)
    end
  end

  defmodule MockTransport do
    alias Archethic.P2P.Client.Transport

    @behaviour Transport

    def handle_connect(_ip, _port) do
      {:ok, make_ref()}
    end

    def handle_close(_socket) do
      :ok
    end

    def handle_send(_socket, "hb") do
      send(self(), {:tcp, make_ref(), "hb"})
      :ok
    end

    def handle_send(_socket, _data), do: :ok

    def handle_message({_, _, data}), do: {:ok, data}
  end

  defmodule MockTransportClosed do
    alias Archethic.P2P.Client.Transport

    @behaviour Transport

    def handle_connect(_ip, _port) do
      {:ok, make_ref()}
    end

    def handle_close(_socket) do
      :ok
    end

    def handle_send(_socket, _), do: :ok

    def handle_message({_, _, _}), do: {:error, :closed}
  end
end
