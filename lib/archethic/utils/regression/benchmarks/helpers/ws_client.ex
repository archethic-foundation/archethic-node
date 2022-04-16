defmodule ArcEthic.Utils.Regression.Helpers.WSClient do
  @moduledoc """
  Websocket client /socket Subscription
  Mint.WebSocket Procesless client
  """

  def create_websocket(host, port, path) do
    {:ok, conn} = Mint.HTTP.connect(:http, "#{host}", port)
    {:ok, conn, ref} = Mint.WebSocket.upgrade(:ws, conn, path, [Mint.WebSocket.PerMessageDeflate])

    http_reply_message =
      receive(do: (message -> message))
      |> IO.inspect(label: "3")

    {:ok, conn, [{:status, ^ref, status}, {:headers, ^ref, resp_headers}, {:done, ^ref}]} =
      Mint.WebSocket.stream(conn, http_reply_message)

    # |> IO.inspect(label: "4")

    {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status, resp_headers)
    # |> IO.inspect(label: "5")

    {conn, websocket, ref}
  end

  def send_message(message, conn, websocket, ref) do
    {:ok, websocket, data} = Mint.WebSocket.encode(websocket, {:text, message})
    {:ok, conn} = Mint.WebSocket.stream_request_body(conn, ref, data)

    server_message = receive(do: (message -> message))

    parse(server_message, conn, websocket, ref)
    |> IO.inspect(label: "server_message")

    server_message = receive(do: (message -> message))

    msg =
      parse(server_message, conn, websocket, ref)
      |> IO.inspect(label: "server_message")

    {conn, websocket, msg, ref}
  end

  def parse(server_message, conn, websocket, ref) do
    {:ok, _conn, [{:data, ^ref, data}]} = Mint.WebSocket.stream(conn, server_message)
    # |> IO.inspect(label: "data")
    {:ok, _websocket, recv_msg} =
      Mint.WebSocket.decode(websocket, data)
      |> IO.inspect(label: "decoded_msg")

    recv_msg
  end

  def close_websocket(conn, websocket, ref) do
    {:ok, websocket, data} = Mint.WebSocket.encode(websocket, :close)
    # |> IO.inspect(label: "6")

    {:ok, conn} = Mint.WebSocket.stream_request_body(conn, ref, data)
    # |> IO.inspect(label: "7")

    close_response = receive(do: (message -> message))
    # |> IO.inspect(label: "8")

    {:ok, conn, [{:data, ^ref, data}]} = Mint.WebSocket.stream(conn, close_response)
    # |> IO.inspect(label: "9")

    {:ok, _websocket, [{:close, 1_000, ""}]} = Mint.WebSocket.decode(websocket, data)
    # |> IO.inspect(label: "10")

    Mint.HTTP.close(conn)
    # |> IO.inspect(label: "11")
  end
end
