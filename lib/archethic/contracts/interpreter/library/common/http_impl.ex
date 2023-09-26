defmodule Archethic.Contracts.Interpreter.Library.Common.HttpImpl do
  @moduledoc """
  Http client for the Smart Contracts.
  Implements AEIP-20.

  Mint library is processless so in order to not mess with
  other processes, we use it from inside a Task.
  """

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Http
  alias Archethic.TaskSupervisor

  use Tag

  @behaviour Http
  @threshold 256 * 1024
  @timeout Application.compile_env(:archethic, [__MODULE__, :timeout], 2_000)
  @allow_http? Application.compile_env(:archethic, [__MODULE__, :allow_http?], false)

  @tag [:io]
  @impl Http
  def request(uri, method, headers \\ %{}, body \\ nil)

  def request(uri, method, headers, body) do
    check_too_many_calls()

    validate_request(uri, method, headers, body)
    headers = format_headers(headers)

    task =
      Task.Supervisor.async_nolink(
        TaskSupervisor,
        fn -> do_request(uri, method, headers, body) end
      )

    case Task.yield(task, @timeout) || Task.shutdown(task) do
      {:ok, {:ok, reply}} ->
        reply

      {:ok, {:error, :threshold_reached}} ->
        raise Library.Error, message: "Http.request/1 response is bigger than threshold"

      {:ok, {:error, :not_https}} ->
        raise Library.Error, message: "Http.request/1 was called with a non https url"

      {:ok, {:error, _}} ->
        # Mint.HTTP.connect error
        # Mint.HTTP.stream error
        raise Library.Error, message: "Http.request/1 failed"

      {:ok, {:error, _, _}} ->
        # Mint.HTTP.request error
        raise Library.Error, message: "Http.request/1 failed"

      nil ->
        # Task.shutdown
        raise Library.Error, message: "Http.request/1 timed out"
    end
  end

  @tag [:io]
  @impl Http
  def request_many(requests) do
    check_too_many_calls()

    requests_count = length(requests)

    if requests_count > 5 do
      raise Library.Error, message: "Http.request_many/1 was called with too many urls"
    end

    requests =
      Enum.map(requests, fn request = %{"url" => url, "method" => method} ->
        headers = Map.get(request, "headers", %{})
        body = Map.get(request, "body", nil)

        validate_request(url, method, headers, body)
        headers = format_headers(headers)

        %{"url" => url, "method" => method, "headers" => headers, "body" => body}
      end)

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      requests,
      fn %{"url" => url, "method" => method, "headers" => headers, "body" => body} ->
        do_request(url, method, headers, body)
      end,
      ordered: true,
      max_concurrency: 5,
      timeout: @timeout,
      on_timeout: :kill_task
    )
    |> Enum.zip(requests)
    # count the number of bytes to be able to send a error too large
    # this is sub optimal because miners might still download threshold N times before returning the error
    # TODO: improve this
    |> Enum.reduce({0, []}, fn
      {{:exit, :timeout}, %{"url" => uri}}, _ ->
        raise Library.Error,
          message: "Http.request_many/1 timed out for url: #{uri}"

      {{:ok, {:error, :threshold_reached}}, %{"url" => uri}}, _ ->
        raise Library.Error,
          message: "Http.request_many/1 response is bigger than threshold for url: #{uri}"

      {{:ok, {:error, :not_https}}, %{"url" => uri}}, _ ->
        raise Library.Error,
          message: "Http.request_many/1 was called with a non https url: #{uri}"

      {{:ok, {:error, _}}, %{"url" => uri}}, _ ->
        # Mint.HTTP.connect error
        # Mint.HTTP.stream error
        raise Library.Error,
          message: "Http.request_many/1 failed for url: #{uri}"

      {{:ok, {:error, _, _}}, %{"url" => uri}}, _ ->
        # Mint.HTTP.request error
        raise Library.Error,
          message: "Http.request_many/1 failed for url: #{uri}"

      {{:ok, {:ok, map}}, _uri}, {bytes_acc, result_acc} ->
        bytes =
          case map["body"] do
            nil -> 0
            body -> byte_size(body)
          end

        {bytes_acc + bytes, result_acc ++ [map]}
    end)
    |> then(fn {bytes_total, results} ->
      if bytes_total > @threshold do
        raise Library.Error,
          message: "Http.request_many/1 sum of responses is bigger than threshold"
      else
        results
      end
    end)
  end

  defp do_request(url, method, headers, request_body) do
    uri = URI.parse(url)

    # we use the transport_opts to be able to test (MIX_ENV=test) with self signed certificates
    conn_opts = [
      transport_opts:
        Application.get_env(:archethic, __MODULE__, [])
        |> Keyword.get(:transport_opts, [])
    ]

    with {:ok, scheme} <- validate_scheme(uri.scheme),
         {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, uri.port, conn_opts),
         {:ok, conn, _} <- Mint.HTTP.request(conn, method, path(uri), headers, request_body),
         {:ok, %{body: response_body, status: status}} <- stream_response(conn) do
      {:ok, %{"status" => status, "body" => response_body}}
    end
  end

  defp validate_scheme("https"), do: {:ok, :https}

  defp validate_scheme("http") do
    if @allow_http? do
      {:ok, :http}
    else
      {:error, :not_https}
    end
  end

  defp validate_scheme(_), do: {:error, :not_https}

  # copied over from Mint
  defp path(uri) do
    IO.iodata_to_binary([
      if(uri.path, do: uri.path, else: ["/"]),
      if(uri.query, do: ["?" | uri.query], else: []),
      if(uri.fragment, do: ["#" | uri.fragment], else: [])
    ])
  end

  defp stream_response(conn, acc0 \\ %{status: 0, data: [], done: false, bytes: 0}) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            acc2 =
              Enum.reduce(responses, acc0, fn
                {:status, _, status}, acc1 ->
                  %{acc1 | status: status}

                {:data, _, data}, acc1 ->
                  %{acc1 | data: acc1.data ++ [data], bytes: acc1.bytes + byte_size(data)}

                {:headers, _, _}, acc1 ->
                  acc1

                {:done, _}, acc1 ->
                  %{acc1 | done: true}
              end)

            cond do
              acc2.bytes > @threshold ->
                {:error, :threshold_reached}

              acc2.done ->
                {:ok, %{status: acc2.status, body: Enum.join(acc2.data)}}

              true ->
                stream_response(conn, acc2)
            end

          {:error, _, reason, _} ->
            {:error, reason}
        end
    end
  end

  defp validate_request(url, method, headers, body)
       when is_binary(url) and is_binary(method) and is_map(headers) and
              (is_binary(body) or is_nil(body)) do
    unless match?({:ok, _}, URI.new(url)),
      do: raise(Library.Error, message: "Http module received invalid url, got #{url}")

    unless method in ["GET", "POST", "PUT", "DELETE", "PATCH"],
      do: raise(Library.Error, message: "Http module received invalid method, got #{method}")

    unless Enum.all?(headers, fn {key, value} -> is_binary(key) and is_binary(value) end),
      do: raise(Library.Error, message: "Http module was called with invalid headers format")
  end

  defp validate_request(_, _, _, _),
    do: raise(Library.Error, message: "Http module received invalid arguments type")

  defp format_headers(headers), do: Map.to_list(headers)

  defp check_too_many_calls() do
    case Process.get(:smart_contract_http_request_called) do
      true -> raise Library.Error, message: "Http module got called more than once"
      _ -> Process.put(:smart_contract_http_request_called, true)
    end
  end
end
