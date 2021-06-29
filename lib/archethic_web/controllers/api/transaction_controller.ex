defmodule ArchEthicWeb.API.TransactionController do
  @moduledoc false

  use ArchEthicWeb, :controller

  alias ArchEthic

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthicWeb.API.TransactionPayload
  alias ArchEthicWeb.ErrorView

  def new(conn, params = %{}) do
    case TransactionPayload.changeset(params) do
      changeset = %{valid?: true} ->
        start = System.monotonic_time()

        res =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.from_map()
          |> ArchEthic.send_new_transaction()

        :telemetry.execute([:archethic, :transaction_end_to_end_validation], %{
          duration: System.monotonic_time() - start
        })

        case res do
          :ok ->
            conn
            |> put_status(201)
            |> json(%{status: "ok"})

          _ ->
            conn
            |> put_status(403)
            |> json(%{status: "error - transaction may be invalid"})
        end

      changeset ->
        conn
        |> put_status(400)
        |> render(ErrorView, "400.json", changeset: changeset)
    end
  end

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           ArchEthic.get_last_transaction(address) do
      mime_type = Map.get(params, "mime", "text/plain")

      etag = Base.encode16(last_address, case: :lower)

      cached? =
        case List.first(get_req_header(conn, "if-none-match")) do
          got_etag when got_etag == etag ->
            true

          _ ->
            false
        end

      conn =
        conn
        |> put_resp_content_type(mime_type, "utf-8")
        |> put_resp_header("content-encoding", "gzip")
        |> put_resp_header("cache-control", "public")
        |> put_resp_header("etag", etag)

      if cached? do
        send_resp(conn, 304, "")
      else
        send_resp(conn, 200, :zlib.gzip(content))
      end
    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
