defmodule ArchethicWeb.API.WebHostingController.Resources do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  use Pathex

  require Logger
  @addresses_key "addresses"
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
        {:error, :is_a_directory, txn}
    end
  end

  def get_metadata(%{"metaData" => metadata, "aewebVersion" => aewebversion}) do
    {:ok, metadata, aewebversion}
  end

  defp get_file(json_content, path), do: get_file(json_content, path, nil)

  # case when we're parsing a reference tx
  defp get_file(file = %{@addresses_key => _}, [], previous_path_item) do
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
        # make sure it is a directory instead of a malformed file
        if Enum.all?(Map.values(json_content), &is_map/1) do
          {:error, :is_a_directory}
        else
          {:error, :malformed}
        end

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

  defp get_file_content(file = %{@addresses_key => address_list}, _cached? = false, url_path) do
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
      encoding = Map.get(file, "encoding")
      {:ok, file_content, encoding}
    rescue
      ArgumentError ->
        :encoding_error

      error ->
        error
    end
  end

  defp get_file_content(_, _, _), do: :file_error
end
