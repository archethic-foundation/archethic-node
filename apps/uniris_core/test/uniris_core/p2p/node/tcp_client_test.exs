defmodule UnirisCore.P2P.NodeTCPClientTest do
  use ExUnit.Case, async: false

  alias UnirisCore.P2P.NodeTCPClient

  defp recv(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        :gen_tcp.send(socket, data |> :erlang.binary_to_term() |> :erlang.term_to_binary())
        recv(socket)

      {:error, _} ->
        :ok
    end
  end

  defp acceptor(socket) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        spawn(fn -> recv(client) end)
        acceptor(socket)

      _ ->
        :error
    end
  end

  setup_all do
    {:ok, socket} = :gen_tcp.listen(7777, [:binary, packet: 4, active: false, reuseaddr: true])
    spawn(fn -> acceptor(socket) end)

    {:ok, %{port: 7777}}
  end

  test "send_message/3 should send a message and get results", %{port: port} do
    assert :hello == NodeTCPClient.send_message({127, 0, 0, 1}, port, :hello)
  end
end
