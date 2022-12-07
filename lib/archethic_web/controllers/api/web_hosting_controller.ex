defmodule ArchethicWeb.API.WebHostingController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction

  alias Archethic.Crypto

  use Pathex

  require Logger

  alias ArchethicWeb.API.WebHostingController.Resources
  alias ArchethicWeb.API.WebHostingController.DirectoryListing

  def web_hosting(conn, params = %{"url_path" => []}) do
    # /web_hosting/:addr redirects to /web_hosting/:addr/
    IO.inspect(params)
    IO.inspect("==")

    if String.last(conn.request_path) != "/" do
      redirect(conn, to: conn.request_path <> "/")
    else
      do_web_hosting(conn, params)
    end
  end

  def web_hosting(conn, params), do: do_web_hosting(conn, params)

  defp do_web_hosting(conn, params) do
    cache_headers = get_cache_headers(conn)

    case get_website(params, cache_headers) do
      {:ok, file_content, encoding, mime_type, cached?, etag} ->
        send_response(conn, file_content, encoding, mime_type, cached?, etag)

      {:error, :invalid_address} ->
        send_resp(conn, 400, "Invalid address")

      {:error, :invalid_content} ->
        send_resp(conn, 400, "Invalid transaction content")

      {:error, :website_not_found} ->
        send_resp(conn, 404, "Cannot find website content")

      {:error, :file_not_found} ->
        send_resp(conn, 404, "Cannot find file content")

        send_resp(conn, 400, "Invalid file encoding")

      {:error, :is_a_directory, txn} ->
        {:ok, listing_html, encoding, mime_type, cached?, etag} =
          DirectoryListing.list(
            conn.request_path,
            params,
            txn,
            cache_headers
          )

        send_response(conn, listing_html, encoding, mime_type, cached?, etag)

      {:error, _} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  def get_txn(address) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, txn = %Transaction{}} <- Archethic.get_last_transaction(address) do
      {:ok, txn}
    else
      er when er in [:error, false] ->
        {:error, :invalid_address}

      {:error, reason} when reason in [:transaction_not_exists, :transaction_invalid] ->
        {:error, :website_not_found}

      error ->
        error
    end
  end

  @doc """
  Fetch the website file content
  """
  @spec get_website(request_params :: map(), cached_headers :: list()) ::
          {:ok, file_content :: binary() | nil, encoding :: binary() | nil, mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
          | {:error, :invalid_address}
          | {:error, :invalid_content}
          | {:error, :file_not_found}
          | {:error, :is_a_directory}
          | {:error, :invalid_encoding}
          | {:error, any()}

  def get_website(params = %{"address" => address}, cache_headers) do
    url_path = Map.get(params, "url_path", [])

    with {:ok, txn} <- get_txn(address),
         {:ok, file_content, encoding, mime_type, cached?, etag} <-
           Resources.load(txn, url_path, cache_headers) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
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
          encoding :: binary() | nil,
          mime_type :: binary(),
          cached? :: boolean(),
          etag :: binary()
        ) ::
          Plug.Conn.t()
  def send_response(conn, file_content, encoding, mime_type, cached?, etag) do
    conn =
      conn
      |> put_resp_content_type(mime_type, "utf-8")
      |> put_resp_header("cache-control", "public")
      |> put_resp_header("etag", etag)

    if cached? do
      send_resp(conn, 304, "")
    else
      {conn, response_content} = encode_res(conn, file_content, encoding)

      send_resp(conn, 200, response_content)
    end
  end

  defp encode_res(conn, file_content, encoding) do
    if Enum.any?(get_req_header(conn, "accept-encoding"), &String.contains?(&1, "gzip")) do
      res_conn = put_resp_header(conn, "content-encoding", "gzip")

      if encoding == "gzip",
        do: {res_conn, file_content},
        else: {res_conn, :zlib.gzip(file_content)}

      # learn lru
    else
      if encoding == "gzip",
        do: {conn, :zlib.gunzip(file_content)},
        else: {conn, file_content}
    end
  end
end
