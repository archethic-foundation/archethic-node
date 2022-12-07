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
         {:ok, metadata, _aeweb_version} <- get_metadata(json_content),
         {:ok, file, mime_type} <- get_file(metadata, url_path),
         {cached?, etag} <- get_cache(cache_headers, last_address, url_path),
         {:ok, file_content, encoding} <- get_file_content(file, cached?, url_path) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
      {:error, :file_not_found} ->
        {:error, :file_not_found}

      {:error, :get_metadata} ->
        {:error, "Error: Cant access metadata and aewebversion, RefTxn: #{last_address}"}

      {:error, :is_a_directory} ->
        {:error, {:is_a_directory, txn}}

      error ->
        error
    end
  end

  def get_metadata(json_content) do
    case json_content do
      %{@metadata_key => metadata, @aewebversion_key => aewebversion} ->
        {:ok, metadata, aewebversion}

      _ ->
        {:error, :get_metadata}
    end
  end

  # index file
  def get_file(metadata, []) do
    case Map.get(metadata, "index.html", :error) do
      :error ->
        {:error, :is_a_directory}

      value ->
        {:ok, value, MIME.from_path("index.html")}
    end
  end

  def get_file(metadata, url_path) do
    resource_path = Enum.join(url_path, @path_seperator)

    case Map.get(metadata, resource_path, :error) do
      :error ->
        {:error, :file_not_found}

      value ->
        {:ok, value, MIME.from_path(resource_path)}
    end
  end

  def get_file_content(_, true, _),
    do: {:ok, nil, nil}

  def get_file_content(
        file_metadata = %{@addresses_key => address_list},
        _cached? = false,
        url_path
      ) do
    resource_path = Enum.join(url_path, @path_seperator)
    resource_path = if resource_path == "", do: "index.html", else: resource_path

    try do
      file_content =
        Enum.reduce(address_list, "", fn address, acc_map ->
          {:ok, address_bin} = Base.decode16(address, case: :mixed)

          {:ok, %Transaction{data: %TransactionData{content: txn_content}}} =
            Archethic.search_transaction(address_bin)

          {:ok, decoded_content} = Jason.decode(txn_content)

          {:ok, res_content} = access(decoded_content, resource_path)

          {:ok, file_content} = Base.url_decode64(res_content, padding: false)

          acc_map <> file_content
        end)

      {:ok, encoding} = access(file_metadata, "encoding")
      {:ok, file_content, encoding}
    rescue
      ArgumentError ->
        :encoding_error

      error ->
        error
    end
  end

  def access(map, key) do
    case Map.get(map, key, :file_not_found) do
      :file_not_found ->
        {:error, :file_not_found}

      data ->
        {:ok, data}
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
