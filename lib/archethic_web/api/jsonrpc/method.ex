defmodule ArchethicWeb.API.JsonRPC.Method do
  @moduledoc """
  Behaviour for Json RPC methods
  """

  @callback validate_params(params :: map() | list()) ::
              {:ok, params :: any()} | {:error, reasons :: list()}

  @callback execute(params :: any()) ::
              {:ok, result :: map() | list()}
              | {:error, reason :: atom(), message :: binary()}
end
