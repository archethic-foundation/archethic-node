defmodule ArchEthic.Utils.Regression.Benchmark.FaucetProvider do
  @moduledoc """
  Behavior for  uco with-drawl from Faucet
  """
  @callback withdraw_uco({atom(), String.t(), number()}, String.t()) ::
              {:ok, any()} | {:error, any()}
end
