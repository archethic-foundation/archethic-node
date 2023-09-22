defmodule Archethic.MockServer do
  @moduledoc """
  Server used in the tests for Smart Contract's module Http
  """
  use Plug.Router

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/" do
    send_resp(conn, 200, "hello")
  end

  get "/very-slow" do
    Process.sleep(5_000)
    send_resp(conn, 200, "slow")
  end

  get "/data" do
    conn = fetch_query_params(conn)
    kbytes = String.to_integer(conn.query_params["kbytes"])
    send_resp(conn, 200, generate_data(kbytes * 1024))
  end

  post "/api" do
    response =
      case conn.body_params do
        %{"method" => "string", "value" => value} -> value
        _ -> "error"
      end

    send_resp(conn, 200, response)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  defp generate_data(bytes) do
    bytes
    |> div(2)
    |> :crypto.strong_rand_bytes()
    |> Base.encode16()
  end
end
