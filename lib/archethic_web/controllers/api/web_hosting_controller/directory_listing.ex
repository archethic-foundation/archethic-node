defmodule ArchethicWeb.API.WebHostingController.DirectoryListing do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  use Pathex

  require Logger
  @addresses_key "addresses"

  @spec list(
          request_path :: String.t(),
          params :: map(),
          transaction :: Transaction.t(),
          cached_headers :: list()
        ) ::
          {:ok, listing_html :: binary() | nil, encoding :: nil | binary(), mime_type :: binary(),
           cached? :: boolean(), etag :: binary()}
  def list(
        request_path,
        params,
        %Transaction{
          address: last_address,
          data: %TransactionData{content: content},
          validation_stamp: %ValidationStamp{timestamp: timestamp}
        },
        cache_headers
      ) do
    url_path = Map.get(params, "url_path", [])
    mime_type = "text/html"

    case get_cache(cache_headers, last_address, url_path) do
      {cached? = true, etag} ->
        {:ok, nil, nil, mime_type, cached?, etag}

      {cached? = false, etag} ->
        case Jason.decode(content) do
          {:error, err = %Jason.DecodeError{}} ->
            {:error, err}

          {:ok, json_content} ->
            assigns =
              do_list(
                request_path,
                url_path,
                elem(get_metadata(json_content), 1),
                timestamp,
                last_address
              )

            {:ok,
             Phoenix.View.render_to_iodata(ArchethicWeb.DirListingView, "index.html", assigns),
             nil, mime_type, cached?, etag}
        end
    end
  end

  def get_metadata(%{"metaData" => metadata, "aewebVersion" => aewebversion}) do
    {:ok, metadata, aewebversion}
  end

  defp do_list(request_path, url_path, json_content, timestamp, last_address) do
    {json_content_subset, current_working_dir, parent_dir_href} =
      case url_path do
        [] ->
          {json_content, "/", nil}

        _ ->
          path = Path.join(url_path)

          subset =
            json_content
            |> Enum.reduce(%{}, fn {key, value}, acc ->
              if String.contains?(key, path) do
                # dir1/file1.txt => file1.txt
                key_relative = key |> String.trim(path <> "/")
                Map.put(acc, key_relative, value)
              else
                acc
              end
            end)

          {
            subset,
            Path.join(["/" | url_path]),
            %{href: request_path |> Path.join("..") |> Path.expand()}
          }
      end

    json_content_subset
    |> Enum.map(fn
      {key, %{@addresses_key => address}} ->
        case Path.split(key) do
          [^key] ->
            {:file, key, address}

          [dir | _] ->
            {:dir, dir}
        end
    end)
    |> Enum.uniq()
    # sort directory last, then DESC order (it will be accumulated in reverse order below)
    |> Enum.sort(fn
      {:file, a, _}, {:file, b, _} ->
        a > b

      {:dir, a}, {:dir, b} ->
        a > b

      {:file, _, _}, {:dir, _} ->
        true

      {:dir, _}, {:file, _, _} ->
        false
    end)
    |> Enum.reduce(%{dirs: [], files: []}, fn
      {:file, name, addresses}, %{dirs: dirs_acc, files: files_acc} ->
        item = %{
          href: %{href: Path.join(request_path, name)},
          last_modified: timestamp,
          addresses: addresses,
          name: name
        }

        %{dirs: dirs_acc, files: [item | files_acc]}

      {:dir, name}, %{dirs: dirs_acc, files: files_acc} ->
        # directories url end with a slash for relative url in website to work
        item = %{
          href: %{href: Path.join([request_path, name]) <> "/"},
          last_modified: timestamp,
          name: name
        }

        %{files: files_acc, dirs: [item | dirs_acc]}
    end)
    |> Enum.into(%{
      cwd: current_working_dir,
      parent_dir_href: parent_dir_href,
      reference_transaction_href: %{
        href:
          Path.join([
            Keyword.fetch!(
              Application.get_env(:archethic, ArchethicWeb.Endpoint),
              :explorer_url
            ),
            "transaction",
            Base.encode16(last_address)
          ])
      }
    })
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
