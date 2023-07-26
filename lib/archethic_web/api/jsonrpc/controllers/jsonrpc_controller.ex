defmodule ArchethicWeb.API.JsonRPCController do
  use ArchethicWeb.API, :controller

  alias Archethic.TaskSupervisor

  alias ArchethicWeb.API.JsonRPC.Error

  alias ArchethicWeb.API.JsonRPC.Method.EstimateTransactionFee
  alias ArchethicWeb.API.JsonRPC.Method.SendTransaction

  require Logger

  @jsonrpc_schema :archethic
                  |> Application.app_dir("priv/json-schemas/jsonrpc-request-2.0.json")
                  |> File.read!()
                  |> Jason.decode!()
                  |> ExJsonSchema.Schema.resolve()

  @methods %{
    "send_transaction" => SendTransaction,
    "estimate_transaction_fee" => EstimateTransactionFee
  }

  @max_batch_size 20

  def rpc(conn, param) do
    requests = wrap_param_in_list(param)

    responses =
      if exceed_max_batch_size?(requests) do
        create_error_response(
          %{"jsonrpc" => "2.0", "id" => nil},
          {:internal_error, "Batch size excedeed limit of #{@max_batch_size}"}
        )
        |> List.wrap()
      else
        execute_request_concurently(requests)
      end

    case responses do
      [response] -> conn |> put_status(:ok) |> json(response)
      responses -> conn |> put_status(:ok) |> json(responses)
    end
  end

  defp wrap_param_in_list(%{"_json" => requests}) when is_list(requests), do: requests
  defp wrap_param_in_list(%{"_json" => request}), do: List.wrap(request)
  defp wrap_param_in_list(param), do: List.wrap(param)

  defp exceed_max_batch_size?(requests), do: length(requests) > @max_batch_size

  defp execute_request_concurently(requests) do
    Task.Supervisor.async_stream(TaskSupervisor, requests, &execute_request/1,
      on_timeout: :kill_task
    )
    |> Enum.zip(requests)
    |> Enum.map(fn
      {{:ok, {:ok, result}}, request} ->
        create_valid_response(request, result)

      {{:ok, {:error, reason}}, request} ->
        create_error_response(request, reason)

      {{:exit, :timeout}, request} ->
        create_error_response(request, {:internal_error, "Timeout while processing request"})

      {{:exit, reason}, request} ->
        Logger.warning("Error while processing Json ROC request: #{inspect(reason)}")
        Logger.debug("Json RPC request: #{inspect(request)}")

        create_error_response(
          request,
          {:internal_error, "Unknown error while processing request"}
        )
    end)
  end

  defp execute_request(request) do
    with :ok <- validate_jsonrpc_format(request),
         :ok <- validate_method_exists(request),
         {:ok, params} <- validate_method_param(request) do
      execute_method(request, params)
    end
  end

  defp validate_jsonrpc_format(request = %{}) when map_size(request) == 0,
    do: {:error, :parse_error}

  defp validate_jsonrpc_format(request = %{}) do
    case ExJsonSchema.Validator.validate(@jsonrpc_schema, request) do
      :ok ->
        :ok

      {:error, reasons} ->
        reasons = Enum.map(reasons, &elem(&1, 0))
        {:error, {:invalid_request, reasons}}
    end
  end

  defp validate_method_exists(%{"method" => method}) do
    if Map.has_key?(@methods, method) do
      :ok
    else
      {:error, {:invalid_method, method}}
    end
  end

  defp validate_method_param(request = %{"method" => method}) do
    params = Map.get(request, "params", %{})
    module = Map.get(@methods, method)

    case module.validate_params(params) do
      {:ok, updated_params} -> {:ok, updated_params}
      {:error, reasons} -> {:error, {:invalid_method_params, reasons}}
    end
  end

  defp execute_method(%{"method" => method}, params) do
    module = Map.get(@methods, method)

    case module.execute(params) do
      {:ok, result} -> {:ok, result}
      {:error, reason, message} -> {:error, {:custom_error, reason, message}}
    end
  end

  defp create_valid_response(request = %{"jsonrpc" => jsonrpc}, result) do
    id = Map.get(request, "id", nil)

    %{"jsonrpc" => jsonrpc, "result" => result, "id" => id}
  end

  defp create_error_response(request = %{"jsonrpc" => jsonrpc}, error) do
    id = Map.get(request, "id", nil)

    %{"jsonrpc" => jsonrpc, "error" => Error.get_error(error), "id" => id}
  end

  defp create_error_response(_, error) do
    %{"jsonrpc" => "2.0", "error" => Error.get_error(error), "id" => nil}
  end
end
