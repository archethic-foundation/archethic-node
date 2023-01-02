defmodule ArchethicWeb.API.WebHostingController.Resources do
  @moduledoc false

  alias Archethic.TransactionChain.{Transaction, TransactionData}

  require Logger

  @spec load(tx :: Transaction.t(), url_path :: list(), cache_headers :: list()) ::
          {:ok, file_content :: binary() | nil, encoding :: binary() | nil, mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
          | {:error,
             :invalid_content
             | :file_not_found
             | {:is_a_directory, tx :: Transaction.t()}
             | :invalid_encoding
             | any()}
  def load(
        tx = %Transaction{
          address: last_address,
          data: %TransactionData{content: content}
        },
        url_path,
        cache_headers
      ) do
    with {:ok, json_content} <- Jason.decode(content),
         {:ok, metadata, _aeweb_version} <- get_metadata(json_content),
         {:ok, file, mime_type, resource_path} <- get_file(metadata, url_path),
         {cached?, etag} <- get_cache(cache_headers, last_address, url_path),
         {:ok, file_content, encoding} <- get_file_content(file, cached?, resource_path) do
      {:ok, file_content, encoding, mime_type, cached?, etag}
    else
      {:error, %Jason.DecodeError{}} ->
        {:error, :invalid_content}

      {:error, :file_not_found} ->
        {:error, :file_not_found}

      {:error, :get_metadata} ->
        {:error, "Error: Cant access metadata and aewebversion, Reftx: #{last_address}"}

      {:error, :is_a_directory} ->
        {:error, {:is_a_directory, tx}}

      error ->
        error
    end
  end

  @spec get_metadata(json_content :: map()) ::
          {:ok, metadata :: map(), aeweb_version :: non_neg_integer()} | {:error, any()}
  def get_metadata(json_content) do
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
          | {:error, :is_a_directory | :file_not_found | :invalid_encoding}
  def get_file(metadata, []) do
    case Map.get(metadata, "index.html", :error) do
      :error ->
        {:error, :is_a_directory}

      value ->
        {:ok, value, MIME.from_path("index.html"), "index.html"}
    end
  end

  def get_file(metadata, url_path) do
    resource_path = Enum.join(url_path, "/")

    case Map.get(metadata, resource_path) do
      nil ->
        if is_a_directory?(metadata, resource_path) do
          {:error, :is_a_directory}
        else
          {:error, :file_not_found}
        end

      file ->
        {:ok, file, MIME.from_path(resource_path), resource_path}
    end
  end

  @spec get_file_content(file_metadata :: map(), cached? :: boolean(), resource_path :: binary()) ::
          {:ok, nil | binary(), nil | binary()}
          | {:error, :encoding_error | :file_not_found | :invalid_encoding | any()}
  def get_file_content(_, true, _), do: {:ok, nil, nil}

  def get_file_content(
        file_metadata = %{"addresses" => address_list},
        _cached? = false,
        resource_path
      ) do
    try do
      file_content =
        Enum.reduce(address_list, "", fn address, acc ->
          {:ok, address_bin} = Base.decode16(address, case: :mixed)

          {:ok, %Transaction{data: %TransactionData{content: tx_content}}} =
            Archethic.search_transaction(address_bin)

          {:ok, decoded_content} = Jason.decode(tx_content)

          {:ok, res_content} = access(decoded_content, resource_path)

          acc <> res_content
        end)

      {:ok, file_content} = Base.url_decode64(file_content, padding: false)
      {:ok, encoding} = access(file_metadata, "encoding", nil)
      {:ok, file_content, encoding}
    rescue
      MatchError ->
        {:error, :invalid_encoding}

      ArgumentError ->
        {:error, :encoding_error}

      error ->
        {:error, error}
    end
  end

  def get_file_content(_, false, _), do: {:error, :file_not_found}

  @spec access(map(), key :: binary(), any()) :: {:error, :file_not_found} | {:ok, any()}
  def access(map, key, default \\ :file_not_found) do
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
end
