defmodule ArchethicWeb.API.WebHostingController.Resources do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  use Pathex

  require Logger
  @addresses_key "addresses"
  @metadata_key "metaData"
  @aewebversion_key "aewebVersion"
  @path_seperator "/"

  def load(
        txn = %Transaction{
          address: last_address,
          data: %TransactionData{content: content}
        },
        url_path,
        cache_headers
      ) do
    with {:ok, json_content} <- Jason.decode(content),
         {:ok, metadata, aeweb_version} <- get_metadata(json_content),
         {:ok, file_content, encoding, mime_type, cached?, etag} <-
           load_resources(metadata, cache_headers, url_path, last_address, aeweb_version) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
      :encoding_error ->
        {:error, :invalid_encoding}

      :file_error ->
        {:error, :file_not_found}

      {:error, %Jason.DecodeError{}} ->
        {:error, :invalid_content}

      {:error, :file_not_found} ->
        {:error, :file_not_found}

      {:error, :malformed} ->
        # malformed file will return 404 as described in test "should return Cannot find file content"
        {:error, :file_not_found}

      {:error, :is_a_directory} ->
        {:error, {:is_a_directory, txn}}
    end
  end

  def get_metadata(%{@metadata_key => metadata, @aewebversion_key => aewebversion}) do
    {:ok, metadata, aewebversion}
  end

  def load_resources(metadata, cache_headers, _path = [], last_address, _version = 1) do
    {cached?, etag} = get_cache(cache_headers, last_address, [])

    index_resource =
      case access(metadata, "index.html") do
        :file_not_found ->
          {:error, :is_a_directory}

        _ ->
          fetch_resource(metadata, "index.html")
      end

    {:ok, index_resource, "gzip", MIME.from_path("index.html"), cached?, etag}
  end

  def load_resources(metadata, cache_headers, url_path, last_address, _version = 1) do

    {cached?, etag} = get_cache(cache_headers, last_address, url_path)
    resource_path = Enum.join(url_path, @path_seperator)
    resource = fetch_resource(metadata, resource_path)
    encoding = access(metadata, "encoding")
    {:ok, resource, encoding, MIME.from_path(resource_path), cached?, etag}
  end

  def fetch_resource(resource_path, metadata, _cached? = false) do
    with {:ok, file_metadata} <- access(metadata, resource_path),
         {:ok, addresses} <- access(file_metadata, @addresses_key) do
    else
      :file_not_found ->
        :file_not_found
    end
  rescue
    :file_not_found ->
      :file_not_found

    _e ->
      :file_error
  end

  def fetch_resource_content(addressses, resource_path) do
    Enum.reduce(addressses, "", fn address, acc_map ->
      file_content =
        with {:ok, address_bin} <- Base.decode16(address, case: :mixed),
             {:ok, %Transaction{} = txn} <- Archethic.search_transaction(),
             content <- access_txn_content(),
             {:ok, txn_content} <- decode_content(),
             {:ok, res_content} <- access(resource_path),
             {:ok, file_content} <- Base.url_decode64(padding: false) do
          acc_map <> file_content
        else
          :error ->
            raise_error(address, resource_path, "Bad Address in Addresses || Bad Base64 encoding")

          e
          when e in [
                 {:error, :transaction_not_exists},
                 {:error, :transaction_invalid},
                 {:error, :network_issue}
               ] ->
            raise_error(address, resource_path, "Transaction error")

          nil ->
            raise_error(address, resource_path, "nil transaction")

          {:error, :json_decode_error} ->
            raise_error(address, resource_path, "json decode error")

          {:error, :file_not_found} ->
            raise_error(address, resource_path, "file not found")
        end
    end)
  rescue
    e when is_bitstring(e) -> {}:e
    e -> " Unknown Error in Rebuilding file content"
  end

  def raise_error(address, resource_path, error_string) do
    raise "Error: #{error_string}, FileTxn: #{address}, Resource: #{resource_path}"
  end

  def access(map, key) do
    case Map.get(map, key, :file_not_found) do
      :file_not_found ->
        {:error, :file_not_found}

      data ->
        {:ok, data}
    end
  end

  def access_txn_content({:ok, txn}) do
    %Transaction{data: %TransactionData{content: content}} = txn
    content
  end

  def decode_content(content) do
    case Jason.decode(content) do
      {:error, _} ->
        {:error, :json_decode_error}

      {:ok, decoded_content} ->
        {:ok, decoded_content}
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
end
