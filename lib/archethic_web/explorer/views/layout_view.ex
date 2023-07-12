defmodule ArchethicWeb.LayoutView do
  @moduledoc false
  use ArchethicWeb, :explorer_view

  def faucet?() do
    Application.get_env(:archethic, ArchethicWeb.FaucetController)
    |> Keyword.get(:enabled, false)
  end
end
