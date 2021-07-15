defmodule ArchEthic.WebClient do
  @moduledoc """
  Functions to query `archethic-node` web api with `Mint`. For use in benchmarks
  and playbooks.
  """

  alias Jason.DecodeError
  alias Mint.{HTTP, Types}

  @doc """
  Execute requests on a `Mint.HTTP.t()` connection.
  """
  @spec with_connection(
          host :: Types.address(),
          port :: :inet.port_number(),
          func :: (HTTP.t() -> {:ok, HTTP.t(), term} | {:error, HTTP.t(), term}),
          proto :: Types.scheme(),
          opts :: keyword()
        ) :: {:ok, term} | {:error, term}
  def with_connection(host, port, func, proto \\ :http, opts \\ []) do
    with {:ok, conn} <- HTTP.connect(proto, host, port, opts),
         {:ok, conn, reply} <- func.(conn),
         {:ok, _onn} <- HTTP.close(conn) do
      {:ok, reply}
    else
      {:error, error} ->
        {:error, error}

      {:error, conn, error} ->
        HTTP.close(conn)
        {:error, error}
    end
  end

  @doc """
  Execute graphql query on a given `Mint.HTTP.t()` connection.
  """
  @spec query(HTTP.t(), String.t()) ::
          {:ok, HTTP.t(), term} | {:error, HTTP.t(), Types.error() | DecodeError.t()}
  def query(conn, query) do
    headers = [{"content-type", "application/graphql"}]

    with {:ok, conn, rsp} <- request(conn, "POST", "/api", headers, query),
         {:ok, data} <- Jason.decode(rsp) do
      {:ok, conn, data}
    else
      {:error, conn, error} -> {:error, conn, error}
      {:error, error} -> {:error, conn, error}
    end
  end

  @doc """
  Execute json request on a given `Mint.HTTP.t()` connection.
  """
  @spec json(conn :: HTTP.t(), path :: String.t(), json :: map() | nil) ::
          {:ok, HTTP.t(), term} | {:error, HTTP.t(), Types.error() | DecodeError.t()}
  def json(conn, path, json \\ nil)

  def json(conn, path, nil) do
    headers = [{"content-type", "application/json"}]

    with {:ok, conn, rsp} <- request(conn, "GET", path, headers, []),
         {:ok, json} <- Jason.decode(rsp) do
      {:ok, conn, json}
    else
      {:error, conn, error} -> {:error, conn, error}
      {:error, error} -> {:error, conn, error}
    end
  end

  def json(conn, path, json) when is_map(json) do
    headers = [{"content-type", "application/json"}]

    with {:ok, body} <- Jason.encode(json),
         {:ok, conn, rsp} <- request(conn, "POST", path, headers, body),
         {:ok, json} <- Jason.decode(rsp) do
      {:ok, conn, json}
    else
      {:error, conn, error} -> {:error, conn, error}
      {:error, error} -> {:error, conn, error}
    end
  end

  @doc """
  Execute request and read full reply on a given `Mint.HTTP.t()` connection.
  """
  @spec request(
          conn :: HTTP.t(),
          method :: String.t(),
          path :: String.t(),
          headers :: Types.headers(),
          body :: iodata() | nil | :stream,
          timeout :: timeout()
        ) :: {:ok, HTTP.t(), term} | {:error, HTTP.t(), Types.error()} | {:error, term}
  def request(conn, method, path, headers \\ [], body \\ [], timeout \\ 5000) do
    with {:ok, conn, ref} <- HTTP.request(conn, method, path, headers, body),
         {:ok, conn, rsp} <- response(conn, ref, timeout) do
      {:ok, conn, rsp}
    else
      {:error, conn, error} -> {:error, conn, error}
      {:error, error} -> {:error, conn, error}
    end
  end

  defp response(conn, ref, timeout, body \\ []) do
    receive do
      message ->
        case HTTP.stream(conn, message) do
          {:ok, conn, partial_response} ->
            case maybe_partial_response(ref, partial_response, body) do
              {body, true} ->
                response(conn, ref, timeout, body)

              {body, false} ->
                {:ok, conn, body}
            end

          :unknown ->
            {:error, :unknown}

          {:error, conn, error, _responce} ->
            {:error, conn, error}
        end
    after
      timeout ->
        {:error, conn, :timeout}
    end
  end

  defp maybe_partial_response(ref, partial_response, body) do
    Enum.reduce(partial_response, {body, true}, fn part, {body, _} ->
      case part do
        {:status, ^ref, _code} ->
          {body, true}

        {:headers, ^ref, _headers} ->
          {body, true}

        {:data, ^ref, data} ->
          {[data | body], true}

        {:done, ^ref} ->
          {Enum.reverse(body), false}
      end
    end)
  end
end
