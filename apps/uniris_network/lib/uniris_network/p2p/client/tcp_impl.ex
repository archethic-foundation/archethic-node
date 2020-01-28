defmodule UnirisNetwork.P2P.Client.TCPImpl do
  @moduledoc false

  alias UnirisNetwork.Node
  alias UnirisNetwork.P2P.Payload

  @tcp_options [:binary, packet: 4, active: false]

  @behaviour UnirisNetwork.P2P.Client.Impl

  @impl true
  @spec send(Node.t(), binary()) :: {:ok, term(), Node.t()} | {:error, :network_issue}
  def send(node = %Node{ ip: ip, port: port}, request) when is_binary(request) do
    case :gen_tcp.connect(String.to_charlist(ip), port, @tcp_options, 2000) do
      {:ok, socket} ->
        Node.available(node.first_public_key)

        with :ok <- :gen_tcp.send(socket, request),
             {:ok, packet} <- :gen_tcp.recv(socket, 0) do
          :gen_tcp.close(socket)

          case Payload.decode(packet) do
            {:ok, data, _} ->
              {:ok, data, node}

            _ ->
              {:error, :network_issue}
          end
        else
          _ ->
            Node.unavailable(node.first_public_key)
            {:error, :network_issue}
        end

      _ ->
        Node.unavailable(node.first_public_key)
        {:error, :network_issue}
    end
  end

end
