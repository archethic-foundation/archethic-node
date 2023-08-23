defmodule ArchethicWeb.API.JsonRPC.Method do
  @moduledoc """
  Behaviour for Json RPC methods
  """

  @callback validate_params(params :: map() | list()) ::
              {:ok, params :: any()} | {:error, reasons :: map()}

  @callback execute(params :: any()) ::
              {:ok, result :: map() | list() | any()}
              | {:error, reason :: atom(), message :: binary()}
              | {:error, reason :: atom(), message :: binary(), data :: any()}
end
