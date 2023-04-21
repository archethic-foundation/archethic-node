defmodule Archethic.OracleChain.Services.Impl do
  @moduledoc false

  @callback cache_child_spec() :: Supervisor.child_spec()
  @callback fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  @callback verify?(%{required(String.t()) => any()}) :: boolean
  @callback parse_data(map()) :: {:ok, map()} | :error
end
