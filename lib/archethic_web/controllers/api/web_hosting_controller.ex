defmodule ArchethicWeb.API.WebHostingController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Crypto

  use Pathex

  require Logger

  @spec web_hosting(Plug.Conn.t(), map) :: Plug.Conn.t()
  def web_hosting(conn, %{"address" => address, "url_path" => url_path}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           Archethic.get_last_transaction(address),
         {:ok, json_content} <- Jason.decode(content),
         {:ok, file, mime_type} <- get_file(json_content, url_path),
         {cached?, etag} <- get_cache(conn, last_address, url_path),
         {:ok, file_content, encodage} <- get_file_content(file, cached?) do
      conn =
        conn
        |> put_resp_content_type(mime_type, "utf-8")
        |> put_resp_header("content-encoding", "gzip")
        |> put_resp_header("cache-control", "public")
        |> put_resp_header("etag", etag)

      if cached? do
        send_resp(conn, 304, "")
      else
        case encodage do
          "gzip" ->
            send_resp(conn, 200, file_content)

          _ ->
            send_resp(conn, 200, :zlib.gzip(file_content))
        end
      end
    else
      # Base.decode16 || Crypto.valid_address
      er when er in [:error, false] ->
        send_resp(conn, 400, "Invalid address")

      # Jason.decode
      {:error, %Jason.DecodeError{}} ->
        send_resp(conn, 400, "Invalid transaction content")

      # Archethic.get_last_transaction
      {:error, _} ->
        send_resp(conn, 400, "Invalid address")

      {:file_not_found, url} ->
        send_resp(conn, 404, "File #{url} does not exist")

      :encodage_error ->
        send_resp(conn, 400, "Invalid file encodage")

      :file_error ->
        send_resp(conn, 400, "Cannot find file content")

      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end

  # API without path returns default index.html file
  @spec get_file(json_content :: map(), url_path :: list()) ::
          {:ok, map(), binary()} | {:file_not_found, binary()}
  defp get_file(json_content, url_path) do
    {json_path, url} =
      case Enum.count(url_path) do
        0 ->
          json_path = path("index.html")
          {json_path, "index.html"}

        1 ->
          file_name = Enum.at(url_path, 0)
          json_path = path(file_name)
          {json_path, file_name}

        _ ->
          json_path = get_json_path(url_path)
          url = Path.join(url_path)
          {json_path, url}
      end

    case Pathex.view(json_content, json_path) do
      {:ok, file} ->
        {:ok, file, MIME.from_path(url)}

      :error ->
        {:file_not_found, url}
    end
  end

  defp get_json_path(url_path) do
    Enum.reduce(url_path, nil, fn value, acc ->
      if acc == nil do
        path(value)
      else
        acc ~> path(value)
      end
    end)
  end

  @spec get_cache(conn :: Plug.Conn.t(), last_address :: binary(), url_path :: list()) ::
          {boolean(), binary()}
  defp get_cache(conn, last_address, url_path) do
    etag =
      case Enum.empty?(url_path) do
        true ->
          Base.encode16(last_address, case: :lower)

        false ->
          Base.encode16(last_address, case: :lower) <> Path.join(url_path)
      end

    cached? =
      case List.first(get_req_header(conn, "if-none-match")) do
        got_etag when got_etag == etag ->
          true

        _ ->
          false
      end

    {cached?, etag}
  end

  # All file are encoded in base64 in JSON content
  @spec get_file_content(file :: map(), cached? :: boolean()) ::
          {:ok, binary(), binary() | nil} | :encodage_error | :file_error
  defp get_file_content(_file, _cached? = true), do: {:ok, nil, nil}

  defp get_file_content(file = %{"content" => content}, _cached = false) do
    try do
      file_content = Base.url_decode64!(content, padding: false)
      encodage = Map.get(file, "encodage")
      {:ok, file_content, encodage}
    rescue
      _ ->
        :encodage_error
    end
  end

  defp get_file_content(_, _), do: :file_error
end
