defmodule ArchethicWeb.AEWeb.WebHostingController do
  @moduledoc false

  use ArchethicWeb.AEWeb, :controller

  alias Archethic.Crypto

  alias ArchethicWeb.AEWeb.WebHostingController.Resources
  alias ArchethicWeb.AEWeb.WebHostingController.DirectoryListing
  alias ArchethicWeb.AEWeb.WebHostingController.ReferenceTransaction

  require Logger

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

    # Normalise/downcase url_paths
    params =
      Map.update!(
        params,
        "url_path",
        fn url ->
          Enum.map(url, &String.downcase/1)
        end
      )

    case get_website(params, cache_headers) do
      {:ok, file_content, encoding, mime_type, cached?, etag} ->
        send_response(conn, file_content, encoding, mime_type, cached?, etag)

      {:error, {:is_a_directory, reference_transaction}} ->
        {:ok, listing_html, encoding, mime_type, cached?, etag} =
          DirectoryListing.list(
            conn.request_path,
            params,
            reference_transaction,
            cache_headers
          )

        send_response(conn, listing_html, encoding, mime_type, cached?, etag)

      {:error, reason} when is_atom(reason) ->
        send_err(conn, reason)

      {:error, _e} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  defp send_err(conn, :invalid_address), do: send_resp(conn, 400, "Invalid address")
  defp send_err(conn, :invalid_content), do: send_resp(conn, 400, "Invalid transaction content")
  defp send_err(conn, :website_not_found), do: send_resp(conn, 404, "Cannot find website content")
  defp send_err(conn, :file_not_found), do: send_resp(conn, 404, "Cannot find file content")
  defp send_err(conn, :invalid_encoding), do: send_resp(conn, 400, "Invalid file encoding")
  defp send_err(conn, :unpublished), do: send_resp(conn, 410, "Website has been unpublished")
  defp send_err(conn, atom), do: send_resp(conn, 400, "Unknown error: #{inspect(atom)}")

  @doc """
  Fetch the website file content
  """
  @spec get_website(params :: map(), cached_headers :: list()) ::
          {:ok, file_content :: binary() | nil, encoding :: binary() | nil, mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
          | {:error, :invalid_address}
          | {:error, :website_not_found}
          | {:error, :invalid_content}
          | {:error, :unpublished}
          | {:error, :file_not_found}
          | {:error, :invalid_encoding}
          | {:error, {:is_a_directory, ReferenceTransaction.t()}}
          | {:error, any()}

  def get_website(params = %{"address" => address}, cache_headers) do
    url_path = Map.get(params, "url_path", [])

    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, reference_transaction} <- ReferenceTransaction.fetch_last(address),
         :ok <- check_published(reference_transaction),
         {:ok, file_content, encoding, mime_type, cached?, etag} <-
           Resources.load(reference_transaction, url_path, cache_headers) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
      er when er in [:error, false] -> {:error, :invalid_address}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_content}
      {:error, :transaction_not_exists} -> {:error, :website_not_found}
      error -> error
    end
  end

  def check_published(%ReferenceTransaction{status: :published}), do: :ok
  def check_published(%ReferenceTransaction{status: :unpublished}), do: {:error, :unpublished}

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
end
