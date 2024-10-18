defmodule ArchethicWeb.AEWeb.WebHostingController.Resources do
  @moduledoc false

  alias Archethic.TransactionChain.{Transaction, TransactionData}
  alias ArchethicCache.LRUDisk
  alias ArchethicWeb.AEWeb.WebHostingController.ReferenceTransaction

  require Logger

  @spec load(
          reference_transaction :: ReferenceTransaction.t(),
          url_path :: list(),
          cache_headers :: list()
        ) ::
          {:ok, file_content :: binary() | nil, encoding :: binary() | nil, mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
          | {:error,
             :file_not_found
             | {:is_a_directory, ReferenceTransaction.t()}
             | :invalid_encoding
             | any()}
  def load(
        reference_transaction = %ReferenceTransaction{
          address: address,
          json_content: json_content
        },
        url_path,
        cache_headers
      ) do
    with {:ok, metadata, _aeweb_version} <- get_metadata(json_content),
         {:ok, file, mime_type, resource_path} <- get_file(metadata, url_path),
         {cached?, etag} <- get_cache(cache_headers, address, url_path),
         {:ok, file_content, encoding} <- get_file_content(file, cached?, resource_path) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
      {:error, :invalid_encoding} ->
        {:error, :invalid_encoding}

      {:error, :file_not_found} ->
        {:error, :file_not_found}

      {:error, :get_metadata} ->
        {:error, "Error: Cant access metadata and aewebversion, Reftx: #{Base.encode16(address)}"}

      {:error, :is_a_directory} ->
        {:error, {:is_a_directory, reference_transaction}}

      error ->
        error
    end
  end

  @spec get_metadata(json_content :: map()) ::
          {:ok, metadata :: map(), aeweb_version :: non_neg_integer()} | {:error, any()}
  defp get_metadata(json_content) do
    case json_content do
      %{"metaData" => metadata, "aewebVersion" => aewebversion} ->
        {:ok, metadata, aewebversion}

      _ ->
        {:error, :get_metadata}
    end
  end

  # index file
  @spec get_file(metadata :: map(), url_path :: list()) ::
          {:ok, file :: map(), mime_type :: binary(), resource_path :: binary()}
          | {:error, :is_a_directory | :file_not_found}
  defp get_file(metadata, []) do
    case Map.get(metadata, "index.html") do
      nil ->
        {:error, :is_a_directory}

      file ->
        {:ok, file, MIME.from_path("index.html"), "index.html"}
    end
  end

  defp get_file(metadata, url_path) do
    resource_path = Enum.join(url_path, "/")

    metadata = normalise_downcase_key(metadata)

    case Map.get(metadata, resource_path) do
      nil ->
        if is_a_directory?(metadata, resource_path) do
          index_path = resource_path <> "/index.html"

          case Map.get(metadata, index_path) do
            nil ->
              {:error, :is_a_directory}

            file ->
              {:ok, file, MIME.from_path("index.html"), index_path}
          end
        else
          # Handle JS History API by serving index.html instead of a 404
          # We loose the ability to return real 404 errors
          case Map.get(metadata, "index.html") do
            nil ->
              {:error, :file_not_found}

            file ->
              {:ok, file, MIME.from_path("index.html"), "index.html"}
          end
        end

      file ->
        {:ok, file, MIME.from_path(resource_path), resource_path}
    end
  end

  @spec get_file_content(file_metadata :: map(), cached? :: boolean(), resource_path :: binary()) ::
          {:ok, nil | binary(), nil | binary()}
          | {:error, :file_not_found | :invalid_encoding | any()}
  defp get_file_content(
         file_metadata = %{"addresses" => address_list},
         _cached? = false,
         resource_path
       ) do
    with {:ok, file_content} <- do_get_file_content(address_list, resource_path),
         {:ok, encoding} <- access(file_metadata, "encoding", nil) do
      {:ok, file_content, encoding}
    end
  end

  defp get_file_content(_, true, _), do: {:ok, nil, nil}
  defp get_file_content(_, _, _), do: {:error, :file_not_found}

  defp do_get_file_content(address_list, resource_path) do
    # started by ArchethicWeb.Supervisor
    cache_server = :web_hosting_cache_file
    cache_key = {address_list, resource_path}

    case LRUDisk.get(cache_server, cache_key) do
      nil ->
        encoded_file_content =
          Enum.reduce(address_list, "", fn address, acc ->
            {:ok, address_bin} = Base.decode16(address, case: :mixed)

            {:ok, %Transaction{data: %TransactionData{content: tx_content}}} =
              Archethic.search_transaction(address_bin)

            {:ok, decoded_content} = Jason.decode(tx_content)

            {:ok, res_content} =
              decoded_content |> normalise_downcase_key() |> access(resource_path)

            acc <> res_content
          end)

        case Base.url_decode64(encoded_file_content, padding: false) do
          {:ok, decoded_file_content} ->
            :telemetry.execute([:archethic_web, :hosting, :cache_file, :miss], %{count: 1})
            LRUDisk.put(cache_server, cache_key, decoded_file_content)
            {:ok, decoded_file_content}

          :error ->
            {:error, :invalid_encoding}
        end

      decoded_file_content ->
        :telemetry.execute([:archethic_web, :hosting, :cache_file, :hit], %{count: 1})
        {:ok, decoded_file_content}
    end
  end

  @spec access(map(), key :: binary(), any()) :: {:error, :file_not_found} | {:ok, any()}
  defp access(map, key, default \\ :file_not_found) do
    case Map.get(map, key, default) do
      :file_not_found ->
        {:error, :file_not_found}

      data ->
        {:ok, data}
    end
  end

  @spec get_cache(cache_headers :: list(), last_address :: binary(), url_path :: list()) ::
          {cached? :: boolean(), etag :: binary()}
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

  @spec is_a_directory?(metadata :: map(), file_path :: binary()) :: boolean()
  defp is_a_directory?(metadata, file_path) do
    # dir1/file1.txt
    # => dir1       should match
    # => file1.txt  should not match
    # => di         should not match
    file_path = file_path <> "/"

    Enum.any?(Map.keys(metadata), fn key ->
      String.starts_with?(key, file_path)
    end)
  end

  # Normalise/downcase map keys
  defp normalise_downcase_key(map) do
    Enum.map(map, fn {key, value} ->
      {String.downcase(key), value}
    end)
    |> Map.new()
  end
end
