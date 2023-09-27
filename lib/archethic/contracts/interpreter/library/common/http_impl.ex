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
  # we use the transport_opts to be able to test (MIX_ENV=test) with self signed certificates
  @conn_opts [
    transport_opts:
      Application.compile_env(:archethic, __MODULE__, []) |> Keyword.get(:transport_opts, [])
  ]

  @tag [:io]
  @impl Http
  def request(uri, method \\ "GET", headers \\ %{}, body \\ nil)

  def request(url, method, headers, body) do
    request = %{"url" => url, "method" => method, "headers" => headers, "body" => body}

    with :ok <- validate_multiple_calls(),
         task <- do_request(request),
         results <- await_tasks_result([request], [task]),
         {:ok, result} <- List.first(results) do
      result
    else
      error -> raise Library.Error, message: format_error_message(error)
    end
  end

  @tag [:io]
  @impl Http
  def request_many(requests) do
    with :ok <- validate_multiple_calls(),
         :ok <- validate_nb_requests(requests),
         requests <- set_request_default(requests),
         tasks <- Enum.map(requests, &do_request/1),
         results <- await_tasks_result(requests, tasks),
         {:ok, results} <- validate_results(results) do
      results
    else
      error -> raise Library.Error, message: format_error_message(error)
    end
  end

  defp validate_multiple_calls() do
    case Process.get(:smart_contract_http_request_called) do
      true ->
        {:error, :multiple_calls}

      _ ->
        Process.put(:smart_contract_http_request_called, true)
        :ok
    end
  end

  defp validate_nb_requests(requests) when length(requests) <= 5, do: :ok
  defp validate_nb_requests(_), do: {:error, :max_nb_requests}

  defp set_request_default(requests) do
    default_request = %{"url" => nil, "method" => "GET", "headers" => %{}, "body" => nil}
    Enum.map(requests, &Map.merge(default_request, &1))
  end

  # -------------- #
  defp do_request(
         request = %{
           "url" => url,
           "method" => method,
           "headers" => headers,
           "body" => request_body
         }
       ) do
    Task.Supervisor.async_nolink(TaskSupervisor, fn ->
      with :ok <- validate_request(url, method, headers, request_body),
           headers <- Map.to_list(headers),
           {:ok, uri} <- URI.new(url),
           {:ok, scheme} <- validate_scheme(uri.scheme),
           {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, uri.port, @conn_opts),
           {:ok, conn, _} <- Mint.HTTP.request(conn, method, path(uri), headers, request_body),
           {:ok, %{body: response_body, status: status}} <- stream_response(conn) do
        {:ok, %{"status" => status, "body" => response_body}}
      else
        {:error, reason} -> {:error, reason, request}
        {:error, _, _} -> {:error, :request_failure, request}
      end
    end)
  end

  # -------------- #
  defp validate_request(url, method, headers, body) do
    with :ok <- validate_url(url),
         :ok <- validate_method(method),
         :ok <- validate_headers(headers) do
      validate_body(body)
    end
  end

  defp validate_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_url}
    end
  end

  defp validate_url(_url), do: {:error, :invalid_url}

  # -------------- #
  defp validate_method(method) when method in ["GET", "POST", "PUT", "DELETE", "PATCH"], do: :ok
  defp validate_method(_method), do: {:error, :invalid_method}

  # -------------- #
  defp validate_headers(headers) when is_map(headers) do
    if Enum.all?(headers, &valid_header?/1), do: :ok, else: {:error, :invalid_headers}
  end

  defp valid_header?({key, value}) when is_binary(key) and is_binary(value), do: true
  defp valid_header?(_), do: false

  # -------------- #
  defp validate_body(body) when is_binary(body) or is_nil(body), do: :ok
  defp validate_body(_), do: {:error, :invalid_body}

  # -------------- #
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

  defp await_tasks_result(requests, tasks) do
    tasks
    |> Task.yield_many(@timeout)
    |> Enum.zip(requests)
    |> Enum.map(fn {{task, res}, request} ->
      case res do
        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout, request}

        {:exit, _reason} ->
          {:error, :task_exited, request}

        {:ok, res} ->
          res
      end
    end)
  end

  defp validate_results(results) do
    # count the number of bytes to be able to send a error too large
    # this is sub optimal because miners might still download threshold N times before returning the error
    # TODO: improve this
    results
    |> Enum.reduce_while({:ok, 0, []}, fn
      {:ok, result}, {:ok, total_bytes, results} ->
        bytes = result |> Map.get("body", "") |> byte_size()
        new_total_bytes = total_bytes + bytes

        if new_total_bytes > @threshold do
          {:halt, {:error, :threshold_reached, %{}}}
        else
          {:cont, {:ok, new_total_bytes, [result | results]}}
        end

      error, _acc ->
        {:halt, error}
    end)
    |> then(fn
      {:ok, _, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end)
  end

  # -------------- #
  defp format_error_message({:error, :multiple_calls}),
    do: "Http module got called more than once"

  defp format_error_message({:error, :max_nb_requests}),
    do: "Http.request_many/1 was called with too many requests"

  defp format_error_message({:error, :invalid_url, %{"url" => url}}),
    do: "Http module received invalid url, got #{inspect(url)}"

  defp format_error_message({:error, :invalid_method, %{"method" => method}}),
    do: "Http module received invalid method, got #{inspect(method)}"

  defp format_error_message({:error, :invalid_headers, %{"headers" => headers}}),
    do: "Http module was called with invalid headers, got #{inspect(headers)}"

  defp format_error_message({:error, :invalid_body, %{"body" => body}}),
    do: "Http module was called with invalid body, got #{inspect(body)}"

  defp format_error_message({:error, :threshold_reached, _}),
    do: "Http response is bigger than threshold"

  defp format_error_message({:error, :not_https, %{"url" => url}}),
    do: "Http request a non https url: #{inspect(url)}"

  defp format_error_message({:error, :timeout, %{"url" => url}}),
    do: "Http request timed out for url #{inspect(url)}"

  defp format_error_message({:error, _, %{"url" => url}}),
    do: "Http request failed for url #{inspect(url)}"
end
