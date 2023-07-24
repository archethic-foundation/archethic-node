defmodule ArchethicWeb.API.JsonRPC.Error do
  @moduledoc """
  Specify the possible error for JsonRPC response
  """

  @doc """
  Return the complete error as 
  ```elixir
    %{"code" => code, "message" => message, "data" => data}
  ```
  """
  @spec get_error(error :: atom() | tuple()) :: map()
  def get_error(:parse_error), do: %{"code" => -32700, "message" => "Parse error"}

  def get_error({:invalid_request, reasons}),
    do: %{"code" => -32600, "message" => "Invalid request", "data" => reasons}

  def get_error({:invalid_method, method}),
    do: %{"code" => -32601, "message" => "Method #{method} not found"}

  def get_error({:invalid_method_params, reasons}),
    do: %{"code" => -32602, "message" => "Invalid params", "data" => reasons}

  def get_error({:internal_error, message}), do: %{"code" => -32603, "message" => message}

  def get_error({:custom_error, reason, message}),
    do: %{"code" => get_custom_code(reason), "message" => message}

  defp get_custom_code(:transaction_exists), do: 122
end
