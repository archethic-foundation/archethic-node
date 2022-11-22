defmodule ArchethicWeb.API.WebHostingController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Crypto

  use Pathex

  require Logger

  def web_hosting(conn, params = %{"url_path" => []}) do
    # /web_hosting/:addr redirects to /web_hosting/:addr/
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

      {:error, :file_not_found} ->
        send_resp(conn, 404, "Cannot find file content")

      {:error, :invalid_encodage} ->
        send_resp(conn, 400, "Invalid file encodage")

      {:error, {:is_a_directory, transaction}} ->
        {:ok, listing_html, encodage, mime_type, cached?, etag} =
          dir_listing(conn.request_path, params, transaction, get_cache_headers(conn))

        send_response(conn, listing_html, encodage, mime_type, cached?, etag)

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
          | {:error, :file_not_found}
          | {:error, :is_a_directory}
          | {:error, :invalid_encodage}
          | {:error, any()}
  def get_website(params = %{"address" => address}, cache_headers) do
    url_path = Map.get(params, "url_path", [])

    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, transaction} <- Archethic.get_last_transaction(address) do
      with {:ok, json_content} <- Jason.decode(transaction.data.content),
           {:ok, file, mime_type} <- get_file(json_content, url_path),
           {cached?, etag} <- get_cache(cache_headers, transaction.address, url_path),
           {:ok, file_content, encodage} <- get_file_content(file, cached?, url_path) do
        {:ok, file_content, encodage, mime_type, cached?, etag}
      else
        :encodage_error ->
          {:error, :invalid_encodage}

        :file_error ->
          {:error, :file_not_found}

        {:error, %Jason.DecodeError{}} ->
          {:error, :invalid_content}

        {:error, :file_not_found} ->
          {:error, :file_not_found}

        {:error, :is_a_directory} ->
          # return the transaction so the dir_listing function do not need to do the I/O
          {:error, {:is_a_directory, transaction}}
      end
    else
      er when er in [:error, false] ->
        {:error, :invalid_address}

      {:error, reason} when reason in [:transaction_not_exists, :transaction_invalid] ->
        {:error, :website_not_found}

      error ->
        error
    end
  end

  @spec dir_listing(
          request_path :: String.t(),
          params :: map(),
          transaction :: Transaction.t(),
          cached_headers :: list()
        ) ::
          {:ok, listing_html :: binary() | nil, encodage :: nil | binary(), mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
  def dir_listing(request_path, params, transaction, cache_headers) do
    url_path = Map.get(params, "url_path", [])

    with {:ok, json_content} <- Jason.decode(transaction.data.content),
         {cached?, etag} <- get_cache(cache_headers, transaction.address, url_path) do
      json_content_subset =
        case url_path do
          [] ->
            json_content

          _ ->
            {:ok, subset} = Pathex.view(json_content, get_json_path(url_path))
            subset
        end

      files_and_dirs =
        Map.keys(json_content_subset)
        |> Enum.map(fn key ->
          case json_content_subset[key] do
            %{"address" => _} ->
              {:file, key}

            _ ->
              {:dir, key}
          end
        end)
        # sort directory last, then DESC order (because we create the binary by the front)
        |> Enum.sort(fn
          {:file, a}, {:file, b} ->
            a > b

          {:dir, a}, {:dir, b} ->
            a > b

          {:file, _}, {:dir, _} ->
            true

          {:dir, _}, {:file, _} ->
            false
        end)

      {current_working_dir, parent_dir_href} =
        case url_path do
          [] ->
            {"/", nil}

          _ ->
            {
              Path.join(["/" | url_path]),
              %{href: request_path |> Path.join("..") |> Path.expand()}
            }
        end

      assigns =
        files_and_dirs
        |> Enum.reduce(%{dirs: [], files: []}, fn
          {file_or_dir, name}, %{dirs: dirs_acc, files: files_acc} ->
            item = %{
              href: %{href: Path.join(request_path, name)},
              last_modified: get_transaction_timestamp(transaction),
              name: name
            }

            case file_or_dir do
              :file ->
                %{dirs: dirs_acc, files: [item | files_acc]}

              :dir ->
                %{files: files_acc, dirs: [item | dirs_acc]}
            end
        end)
        |> Enum.into(%{
          cwd: current_working_dir,
          parent_dir_href: parent_dir_href
        })

      {:ok, Phoenix.View.render_to_iodata(ArchethicWeb.DirListingView, "index.html", assigns),
       nil, "text/html", cached?, etag}
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

  defp get_file(json_content, path), do: get_file(json_content, path, nil)

  # case when we're parsing a reference tx
  defp get_file(file = %{"address" => _}, [], previous_path_item) do
    {:ok, file, MIME.from_path(previous_path_item)}
  end

  # case when we're parsing a storage tx
  defp get_file(file, [], previous_path_item) when is_binary(file) do
    {:ok, file, MIME.from_path(previous_path_item)}
  end

  # case when we're on a directory
  defp get_file(json_content, [], _previous_path_item) when is_map(json_content) do
    case Map.get(json_content, "index.html") do
      nil ->
        {:error, :is_a_directory}

      file ->
        {:ok, file, "text/html"}
    end
  end

  # recurse until we are on the end of path
  defp get_file(json_content, [path_item | rest], _previous_path_item) do
    case Map.get(json_content, path_item) do
      nil ->
        #
        {:error, :file_not_found}

      json_content_subset ->
        get_file(json_content_subset, rest, path_item)
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

  defp get_transaction_timestamp(transaction) do
    case transaction.validation_stamp do
      nil ->
        # should happen only in the tests
        DateTime.utc_now()

      validation_stamp ->
        validation_stamp.timestamp
    end
  end
end
