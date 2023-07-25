defmodule ArchethicWeb.Explorer.LayoutView do
  @moduledoc false
  use ArchethicWeb.Explorer, :view

  def faucet?() do
    Application.get_env(:archethic, ArchethicWeb.Explorer.FaucetController)
    |> Keyword.get(:enabled, false)
  end
end
