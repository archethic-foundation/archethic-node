defmodule ArchethicWeb.API.WebHostingController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias ArchethicWeb.API.WebHosting.CheckSum
  alias Archethic.Crypto

  use Pathex

  require Logger

  def web_hosting(conn, params = %{"url_path" => []}) do
    if String.last(conn.request_path) != "/" do
      redirect(conn, to: conn.request_path <> "/")
    else
      do_web_hosting(conn, params)
    end
  end

  def web_hosting(conn, params), do: do_web_hosting(conn, params)

  defp do_web_hosting(conn, params) do
    case get_website(params, get_cache_headers(conn)) do
      {:ok, file_content, encodage, mime_type, cached?, etag} ->
        send_response(conn, file_content, encodage, mime_type, cached?, etag)

      {:error, :invalid_address} ->
        send_resp(conn, 400, "Invalid address")

      {:error, :invalid_content} ->
        send_resp(conn, 400, "Invalid transaction content")

      {:error, :website_not_found} ->
        send_resp(conn, 404, "Cannot find website content")

      {:error, :not_found} ->
        send_resp(conn, 404, "Cannot find file content")

      {:error, :invalid_encodage} ->
        send_resp(conn, 400, "Invalid file encodage")

      {:error, _} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  @doc """
  Fetch the website file content
  """
  @spec get_website(request_params :: map(), cached_headers :: list()) ::
          {:ok, file_content :: binary() | nil, encodage :: binary() | nil, mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
          | {:error, :invalid_address}
          | {:error, :invalid_content}
          | {:error, :not_found}
          | {:error, :invalid_encodage}
          | {:error, any()}
  def get_website(params = %{"address" => address}, cache_headers) do
    url_path = Map.get(params, "url_path", [])

    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           Archethic.get_last_transaction(address),
         {:ok, json_content} <- Jason.decode(content),
         {:ok, file, mime_type} <-
           get_file(json_content, url_path),
         {cached?, etag} <-
           get_cache(cache_headers, last_address, url_path),
         {:ok, file_content, encodage} <-
           get_file_content(file, cached?, url_path) do
      {:ok, file_content, encodage, mime_type, cached?, etag}
    else
      er when er in [:error, false] ->
        {:error, :invalid_address}

      {:error, %Jason.DecodeError{}} ->
        {:error, :invalid_content}

      {:error, reason} when reason in [:transaction_not_exists, :transaction_invalid] ->
        {:error, :website_not_found}

      {:file_not_found, _url} ->
        {:error, :not_found}

      :encodage_error ->
        {:error, :invalid_encodage}

      :file_error ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Return the list of headers for caching
  """
  @spec get_cache_headers(Plug.Conn.t()) :: list()
  def get_cache_headers(conn), do: get_req_header(conn, "if-none-match")

  @doc """
  Send the website file content with the cache and encoding policy
  """
  @spec send_response(
          Plug.Conn.t(),
          file_content :: binary() | nil,
          encodage :: binary() | nil,
          mime_type :: binary(),
          cached? :: boolean(),
          etag :: binary()
        ) ::
          Plug.Conn.t()
  def send_response(conn, file_content, encodage, mime_type, cached?, etag) do
    conn =
      conn
      |> put_resp_content_type(mime_type, "utf-8")
      |> put_resp_header("cache-control", "public")
      |> put_resp_header("etag", etag)

    if cached? do
      send_resp(conn, 304, "")
    else
      {conn, response_content} = encode_res(conn, file_content, encodage)

      send_resp(conn, 200, response_content)
    end
  end

  defp encode_res(conn, file_content, encodage) do
    if Enum.any?(get_req_header(conn, "accept-encoding"), &String.contains?(&1, "gzip")) do
      res_conn = put_resp_header(conn, "content-encoding", "gzip")

      if encodage == "gzip",
        do: {res_conn, file_content},
        else: {res_conn, :zlib.gzip(file_content)}
    else
      if encodage == "gzip",
        do: {conn, :zlib.gunzip(file_content)},
        else: {conn, file_content}
    end
  end

  # API without path returns default index.html file
  # or the only file if there is only one
  defp get_file(json_content, url_path) do
    {json_path, url} =
      case Enum.count(url_path) do
        0 ->
          file_name = get_single_file_name(json_content)
          json_path = path(file_name)
          {json_path, file_name}

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

  defp get_single_file_name(json_content) do
    keys = Map.keys(json_content)

    case Enum.count(keys) do
      1 ->
        # Control if it is a file or a folder
        file_name = Enum.at(keys, 0)
        file_content = Map.get(json_content, file_name)

        if !is_map(file_content) or Map.has_key?(file_content, "address") do
          file_name
        else
          "index.html"
        end

      _ ->
        "index.html"
    end
  end

  defp get_cache(cache_headers, last_address, url_path) do
    etag =
      case Enum.empty?(url_path) do
        true ->
          Base.encode16(last_address, case: :lower)

        false ->
          Base.encode16(last_address, case: :lower) <> Path.join(url_path)
      end

    cached? =
      case List.first(cache_headers) do
        got_etag when got_etag == etag ->
          true

        _ ->
          false
      end

    {cached?, etag}
  end

  # All file are encoded in base64 in JSON content
  defp get_file_content(_file, _cached? = true, _url_path), do: {:ok, nil, nil}

  defp get_file_content(file = %{"address" => address_list}, _cached? = false, url_path) do
    try do
      content =
        Enum.map_join(address_list, fn tx_address ->
          {:ok, %Transaction{data: %TransactionData{content: content}}} =
            Base.decode16!(tx_address, case: :mixed) |> Archethic.search_transaction()

          {:ok, json_content} = Jason.decode(content)
          {:ok, nested_file_content, _} = get_file(json_content, url_path)

          nested_file_content
        end)

      file_content = Base.url_decode64!(content, padding: false)
      encodage = Map.get(file, "encodage")
      {:ok, file_content, encodage}
    rescue
      ArgumentError ->
        :encodage_error

      error ->
        error
    end
  end

  defp get_file_content(_, _, _), do: :file_error

  def checksum(conn, %{"ref_address" => ref_address}) do
    with {:ok, addr_binary} <-
           Base.decode16(ref_address, case: :mixed),
         true <- Crypto.valid_address?(addr_binary),
         {:data, file_hash} <- CheckSum.get_checksum(addr_binary) do
      conn
      |> put_status(200)
      |> json(file_hash)
    else
      _e ->
        send_resp(conn, 400, "error")
    end
  end
end
