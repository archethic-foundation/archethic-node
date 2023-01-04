defmodule ArchethicWeb.API.WebHostingController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic.{
    Crypto,
    TransactionChain.Transaction,
    TransactionChain.Transaction.ValidationStamp,
    TransactionChain.TransactionData
  }

  alias ArchethicCache.LRU

  require Logger

  alias ArchethicWeb.API.WebHostingController.{Resources, DirectoryListing}

  @spec web_hosting(Plug.Conn.t(), params :: map()) :: Plug.Conn.t()
  def web_hosting(conn, params = %{"url_path" => []}) do
    # /web_hosting/:addr redirects to /web_hosting/:addr/
    if String.last(conn.request_path) != "/" do
      redirect(conn, to: conn.request_path <> "/")
    else
      do_web_hosting(conn, params)
    end
  end

  def web_hosting(conn, params), do: do_web_hosting(conn, params)

  @spec do_web_hosting(Plug.Conn.t(), params :: map()) :: Plug.Conn.t()
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

      {:error, :invalid_encoding} ->
        send_resp(conn, 400, "Invalid file encoding")

      {:error, {:is_a_directory, reference_transaction}} ->
        {:ok, listing_html, encoding, mime_type, cached?, etag} =
          DirectoryListing.list(
            conn.request_path,
            params,
            reference_transaction,
            cache_headers
          )

        send_response(conn, listing_html, encoding, mime_type, cached?, etag)

      {:error, _e} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  @doc """
  Fetch the website file content
  """
  @spec get_website(params :: map(), cached_headers :: list()) ::
          {:ok, file_content :: binary() | nil, encoding :: binary() | nil, mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
          | {:error, :invalid_address}
          | {:error, :website_not_found}
          | {:error, :invalid_content}
          | {:error, :file_not_found}
          | {:error, :invalid_encoding}
          | {:error, {:is_a_directory, {binary(), map(), DateTime.t()}}}
          | {:error, any()}

  def get_website(params = %{"address" => address}, cache_headers) do
    url_path = Map.get(params, "url_path", [])

    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, last_address} <- Archethic.get_last_transaction_address(address),
         {:ok, reference_transaction} <- get_reference_transaction(last_address),
         {:ok, file_content, encoding, mime_type, cached?, etag} <-
           Resources.load(reference_transaction, url_path, cache_headers) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
      er when er in [:error, false] ->
        {:error, :invalid_address}

      {:error, %Jason.DecodeError{}} ->
        {:error, :invalid_content}

      {:error, reason} when reason in [:transaction_not_exists, :transaction_invalid] ->
        {:error, :website_not_found}

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
    else
      if encoding == "gzip",
        do: {conn, :zlib.gunzip(file_content)},
        else: {conn, file_content}
    end
  end

  # Fetch the reference transaction either from cache, or from the network.
  #
  # Instead of returning the entire transaction,
  # we return a triplet with only the formatted data we need
  @spec get_reference_transaction(binary()) ::
          {:ok, {binary(), map(), DateTime.t()}} | {:error, term()}
  defp get_reference_transaction(address) do
    # started by ArchethicWeb.Supervisor
    cache_server = :web_hosting_cache_ref_tx
    cache_key = address

    case LRU.get(cache_server, cache_key) do
      nil ->
        with {:ok,
              %Transaction{
                data: %TransactionData{content: content},
                validation_stamp: %ValidationStamp{timestamp: timestamp}
              }} <- Archethic.search_transaction(address),
             {:ok, json_content} <- Jason.decode(content) do
          reference_transaction = {address, json_content, timestamp}
          LRU.put(cache_server, cache_key, reference_transaction)
          {:ok, reference_transaction}
        end

      reference_transaction ->
        {:ok, reference_transaction}
    end
  end
end
