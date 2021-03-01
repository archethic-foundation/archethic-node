defmodule Uniris.OracleChain.Services.Impl do
  @moduledoc false

  @callback fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  @callback verify?(%{required(String.t()) => any()}) :: boolean
end
