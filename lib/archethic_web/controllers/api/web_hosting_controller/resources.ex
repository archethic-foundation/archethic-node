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

  def load_resources(
        metadata,
        cache_headers,
        url_path,
        last_address,
        _aeweb_version = 1
      ) do
    file_path = Enum.join(url_path, "/")

    file_content =
      case Map.get(metadata, file_path) do
        nil ->
          if Enum.any?(Map.keys(metadata), &String.starts_with?(&1, file_path)) do
            # it is a directory

            # if there is an index.html serve it
            case Map.get(metadata, Path.join(file_path, "index.html")) do
              nil ->
                {:error, :is_a_directory}

              file ->
                get_file_content(file, file_path)
            end
          else
            {:error, :file_not_found}
          end

        file ->
          get_file_content(file, file_path)
      end

    case file_content do
      {:ok, content} ->
        {cached?, etag} = get_cache(cache_headers, last_address, url_path)
        {:ok, content, "gzip", MIME.from_path(file_path), cached?, etag}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_file_content(file, file_path) do
    content =
      Map.get(file, @addresses_key)
      |> Enum.reduce("", fn address, acc_map ->
        content =
          Base.decode16!(address, case: :mixed)
          |> Archethic.search_transaction()
          |> elem(1)
          |> get_in([Access.key(:data), Access.key(:content)])
          |> Jason.decode()
          |> elem(1)
          |> Map.get(file_path)
          |> Base.url_decode64!(padding: false)

        acc_map <> content
      end)

    {:ok, content}
  rescue
    error ->
      Logger.warn("Impossible to read file's content at #{file_path}",
        file: file,
        error: error
      )

      {:error, :file_error}
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
