defmodule Archethic.Contracts.Interpreter.Library.Http do
  @moduledoc false

  @behaviour Archethic.Contracts.Interpreter.Library
  @threshold 256 * 1024

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  def error_not_https(), do: -4003
  def error_timeout(), do: -4000
  def error_too_large(), do: -4002
  def error_other(), do: -4001

  def fetch(uri) do
    uri = URI.parse(uri)

    with "https" <- uri.scheme,
         {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port),
         {:ok, conn, _} <- Mint.HTTP.request(conn, "GET", path(uri), [], nil) do
      case stream_response(conn) do
        {:ok, %{body: body, status: status}} ->
          %{
            "status" => status,
            "body" => body
          }

        {:error, :timeout} ->
          %{"status" => error_timeout()}

        {:error, :threshold_reached} ->
          %{"status" => error_too_large()}

        {:error, _} ->
          %{"status" => error_other()}
      end
    else
      "http" ->
        %{"status" => error_not_https()}

      # we handle nxdomain as 404
      _ ->
        %{"status" => 404}
    end
  end

  def fetch_many(uris) do
    if length(uris) > 5 do
      throw("Tried to Http.fetch_many/1 with more than 5 urls")
    end

    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      uris,
      &fetch/1,
      ordered: true,
      max_concurrency: 5
    )
    |> Enum.to_list()

    [
      %{
        "status" => 200,
        "body" => "{\"result\": 42}"
      },
      %{
        "status" => 200,
        "body" => "{\"result\": 43}"
      }
    ]
  end

  def check_types(:fetch, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:fetch_many, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false

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
              Enum.reduce(responses, acc0, fn response, acc1 ->
                case response do
                  {:status, _, status} ->
                    %{acc1 | status: status}

                  {:data, _, data} ->
                    %{acc1 | data: acc1.data ++ [data], bytes: acc1.bytes + byte_size(data)}

                  {:headers, _, _} ->
                    acc1

                  {:done, _} ->
                    %{acc1 | done: true}
                end
              end)

            cond do
              acc2.done ->
                {:ok, %{status: acc2.status, body: Enum.join(acc2.data)}}

              acc2.bytes > @threshold ->
                {:error, :threshold_reached}

              true ->
                stream_response(conn, acc2)
            end

          {:error, _, reason, _} ->
            {:error, reason}
        end
    after
      2_000 ->
        {:error, :timeout}
    end
  end
end
