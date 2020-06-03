defmodule UnirisWeb.TransactionController do
  use UnirisWeb, :controller

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <- UnirisCore.get_last_transaction(address) do

      mime_type = Map.get(params, "mime", "text/plain")

      etag = Base.encode16(last_address, case: :lower)
      status = case List.first(Plug.Conn.get_req_header(conn, "if-none-match")) do
        got_etag when got_etag == etag ->
          304
        _ ->
          200
      end

      conn
      |> put_resp_content_type(mime_type, "utf-8")
      |> put_resp_header("content-encoding", "gzip")
      |> put_resp_header("cache-control", "public")
      |> put_resp_header("etag", etag)
      |> send_resp(status, :zlib.gzip(content))

    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end

end
