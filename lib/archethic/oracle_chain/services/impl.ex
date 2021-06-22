defmodule ArchEthic.OracleChain.Services.Impl do
  @moduledoc false

  @callback fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  @callback verify?(%{required(String.t()) => any()}) :: boolean
  @callback parse_data(map()) :: {:ok, map()} | :error
end
