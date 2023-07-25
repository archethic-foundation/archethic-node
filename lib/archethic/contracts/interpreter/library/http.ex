defmodule Archethic.Contracts.Interpreter.Library.Http do
  @moduledoc """
  Http client for the Smart Contracts.
  Implements AEIP-20.

  Mint library is processless so in order to not mess with
  other processes, we use it from inside a Task.
  """

  @behaviour Archethic.Contracts.Interpreter.Library
  @threshold 256 * 1024

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.TaskSupervisor

  def error_other(), do: -4000
  def error_timeout(), do: -4001
  def error_too_large(), do: -4002
  def error_too_many(), do: -4003
  def error_not_https(), do: -4004

  def fetch(uri) do
    task =
      Task.Supervisor.async_nolink(
        TaskSupervisor,
        fn -> do_fetch(uri) end
      )

    case Task.yield(task, 2_000) || Task.shutdown(task) do
      {:ok, reply} ->
        reply

      _ ->
        error_status(error_timeout())
    end
  end

  def fetch_many(uris) do
    uris_count = length(uris)

    if uris_count > 5 do
      for _ <- 1..uris_count, do: error_status(error_too_many())
    else
      Task.Supervisor.async_stream_nolink(
        TaskSupervisor,
        uris,
        &fetch/1,
        ordered: true,
        max_concurrency: 5,
        on_timeout: :kill_task
      )
      |> Enum.to_list()
      # count the number of bytes to be able to send a error too large
      # this is sub optimal because miners might still download threshold N times before returning the error
      # TODO: improve this
      |> Enum.reduce({0, []}, fn
        {:ok, map}, {bytes_acc, result_acc} ->
          bytes =
            case map["body"] do
              nil -> 0
              body -> byte_size(body)
            end

          {bytes_acc + bytes, result_acc ++ [map]}

        {:exit, :timeout}, {bytes_acc, result_acc} ->
          # should not be triggered since default timeout of 5_000 is much longer
          # than fetch/1 timeout (2_000)
          {bytes_acc, result_acc ++ [error_status(error_timeout())]}
      end)
      |> then(fn {bytes_total, result} ->
        if bytes_total > @threshold do
          for _ <- 1..uris_count, do: error_status(error_too_large())
        else
          result
        end
      end)
    end
  end

  def check_types(:fetch, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:fetch_many, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false

  defp do_fetch(uri) do
    uri = URI.parse(uri)

    # we use the transport_opts to be able to test (MIX_ENV=test) with self signed certificates
    conn_opts = [
      transport_opts:
        Application.get_env(:archethic, __MODULE__, [])
        |> Keyword.get(:transport_opts, [])
    ]

    with "https" <- uri.scheme,
         {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port, conn_opts),
         {:ok, conn, _} <- Mint.HTTP.request(conn, "GET", path(uri), [], nil) do
      case stream_response(conn) do
        {:ok, %{body: body, status: status}} ->
          %{
            "status" => status,
            "body" => body
          }

        {:error, :threshold_reached} ->
          error_status(error_too_large())

        {:error, _} ->
          error_status(error_other())
      end
    else
      "http" ->
        error_status(error_not_https())

      # we handle nxdomain/econnrefused as 404
      _ ->
        error_status(404)
    end
  end

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

  defp error_status(status) do
    # we prefer body to be "" instead of nil
    # so sc developers do not have to check for nil
    %{"status" => status, "body" => ""}
  end
end
