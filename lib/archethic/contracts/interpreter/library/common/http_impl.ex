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
  @supported_schemes Application.compile_env(
                       :archethic,
                       [__MODULE__, :supported_schemes],
                       ["https"]
                     )
  # we use the transport_opts to be able to test (MIX_ENV=test) with self signed certificates
  @conn_opts [
    transport_opts:
      :archethic |> Application.compile_env(__MODULE__, []) |> Keyword.get(:transport_opts, [])
  ]

  @tag [:io]
  @impl Http
  def request(uri, method \\ "GET", headers \\ %{}, body \\ nil, throw_on_error \\ true)

  def request(url, method, headers, body, throw_on_error) do
    [%{"url" => url, "method" => method, "headers" => headers, "body" => body}]
    |> request_many(throw_on_error)
    |> List.first()
  end

  @tag [:io]
  @impl Http
  def request_many(requests, throw_on_err \\ true)

  def request_many(requests, true) do
    with :ok <- validate_multiple_calls(),
         :ok <- validate_nb_requests(requests),
         requests <- set_request_default(requests),
         tasks <- Enum.map(requests, &do_request/1),
         results <- await_tasks_result(requests, tasks),
         {:ok, results} <- validate_results(results, true) do
      results
    else
      error -> raise Library.Error, message: format_error_message(error)
    end
  end

  def request_many(requests, false) do
    case validate_multiple_calls() do
      {:error, :multiple_calls} ->
        Enum.map(requests, fn _ -> %{"status" => -4005} end)

      :ok ->
        {requests_to_handle, requests_not_handled} = Enum.split(requests, 5)

        tasks =
          requests_to_handle
          |> set_request_default()
          |> Enum.map(&do_request/1)

        {:ok, results} =
          requests_to_handle
          |> await_tasks_result(tasks)
          |> validate_results(false)

        transform_results(
          results ++ Enum.map(requests_not_handled, &{:error, :max_nb_requests, &1})
        )
    end
  end

  defp transform_results(results) do
    Enum.map(results, fn
      {:ok, result} ->
        result

      {:error, :max_nb_requests, _} ->
        %{"status" => -4003}

      {:error, :threshold_reached, _} ->
        %{"status" => -4002}

      {:error, :timeout, _} ->
        %{"status" => -4001}

      {:error, :request_failure, _} ->
        %{"status" => -4000}

      {:error, :invalid_url, _} ->
        %{"status" => -4000}

      {:error, :invalid_method, _} ->
        %{"status" => -4000}

      {:error, :invalid_headers, _} ->
        %{"status" => -4000}

      {:error, :invalid_body, _} ->
        %{"status" => -4000}

      {:error, :not_supported_scheme, _} ->
        %{"status" => -4004}
    end)
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
  defp validate_scheme(scheme) when scheme in @supported_schemes,
    do: {:ok, String.to_existing_atom(scheme)}

  defp validate_scheme(_), do: {:error, :not_supported_scheme}

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

  defp validate_results(results, true) do
    # count the number of bytes to be able to send a error too large
    # this is sub optimal because miners might still download threshold N times before returning the error
    # TODO: improve this
    results
    |> Enum.reduce_while({:ok, 0, []}, fn
      {:ok, result}, {:ok, total_bytes, acc} ->
        bytes = result |> Map.get("body", "") |> byte_size()
        new_total_bytes = total_bytes + bytes

        if new_total_bytes > @threshold do
          {:halt, {:error, :threshold_reached, %{}}}
        else
          {:cont, {:ok, new_total_bytes, [result | acc]}}
        end

      error, _acc ->
        {:halt, error}
    end)
    |> then(fn
      {:ok, _, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end)
  end

  defp validate_results(results, false) do
    # count the number of bytes to be able to send a error too large
    # this is sub optimal because miners might still download threshold N times before returning the error
    # TODO: improve this
    results
    |> Enum.reduce_while({0, []}, fn
      {:ok, result}, {total_bytes, acc} ->
        bytes = result |> Map.get("body", "") |> byte_size()
        new_total_bytes = total_bytes + bytes

        if new_total_bytes > @threshold do
          {:halt, {:error, :threshold_reached, %{}}}
        else
          {:cont, {new_total_bytes, [{:ok, result} | acc]}}
        end

      error, {total_bytes, acc} ->
        {:cont, {total_bytes, [error | acc]}}
    end)
    |> then(fn
      {:error, :threshold_reached, %{}} ->
        # when threshold_reached we apply this error to all requests
        {:ok, Enum.map(results, fn _ -> {:error, :threshold_reached, %{}} end)}

      {_bytes, acc} ->
        {:ok, Enum.reverse(acc)}
    end)
  end

  # -------------- #
  defp format_error_message({:error, :multiple_calls}),
    do: "Http module got called more than once"

  defp format_error_message({:error, :max_nb_requests}),
    do: "Http.request_many was called with too many requests"

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

  defp format_error_message({:error, :not_supported_scheme, %{"url" => url}}),
    do:
      "Http request was called with an invalid scheme for #{inspect(url)}, " <>
        "supported scheme are #{Enum.join(@supported_schemes, ", ")}"

  defp format_error_message({:error, :timeout, %{"url" => url}}),
    do: "Http request timed out for url #{inspect(url)}"

  defp format_error_message({:error, _, %{"url" => url}}),
    do: "Http request failed for url #{inspect(url)}"
end
