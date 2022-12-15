defmodule ArchethicWeb.API.TransactionController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.{
    Transaction,
    TransactionData
  }

  alias Archethic.Mining
  alias Archethic.OracleChain

  alias ArchethicWeb.API.TransactionPayload
  alias ArchethicWeb.ErrorView
  alias ArchethicWeb.TransactionSubscriber

  require Logger

  def new(conn, params = %{}) do
    case TransactionPayload.changeset(params) do
      changeset = %{valid?: true} ->
        tx =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.cast()

        tx_address = tx.address

        try do
          if Archethic.transaction_exists?(tx_address) do
            conn |> put_status(422) |> json(%{status: "error - transaction already exists!"})
          else
            send_transaction(conn, tx)
          end
        catch
          e ->
            Logger.error("Cannot get transaction summary - #{inspect(e)}")
            conn |> put_status(504) |> json(%{status: "error - networking error"})
        end

      changeset ->
        Logger.debug(
          "Invalid transaction #{inspect(Ecto.Changeset.traverse_errors(changeset, &ArchethicWeb.ErrorHelpers.translate_error/1))}"
        )

        conn
        |> put_status(400)
        |> put_view(ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end

  defp send_transaction(conn, tx = %Transaction{}) do
    case Archethic.send_new_transaction(tx) do
      :ok ->
        TransactionSubscriber.register(tx.address, System.monotonic_time())

        conn
        |> put_status(201)
        |> json(%{
          transaction_address: Base.encode16(tx.address),
          status: "pending"
        })

      {:error, :network_issue} ->
        conn
        |> put_status(422)
        |> json(%{status: "error - transaction may be invalid"})
    end
  end

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           Archethic.get_last_transaction(address) do
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

  def transaction_fee(conn, tx) do
    case TransactionPayload.changeset(tx) do
      changeset = %{valid?: true} ->
        timestamp = DateTime.utc_now()

        previous_price =
          timestamp
          |> OracleChain.get_last_scheduling_date()
          |> OracleChain.get_uco_price()

        uco_eur = previous_price |> Keyword.fetch!(:eur)
        uco_usd = previous_price |> Keyword.fetch!(:usd)

        fee =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.cast()
          |> Mining.get_transaction_fee(uco_usd, timestamp)

        conn
        |> put_status(:ok)
        |> json(%{
          "fee" => fee,
          "rates" => %{
            "usd" => uco_usd,
            "eur" => uco_eur
          }
        })

      changeset ->
        conn
        |> put_status(:bad_request)
        |> put_view(ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end
end
