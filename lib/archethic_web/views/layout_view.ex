defmodule ArchEthicWeb.LayoutView do
  @moduledoc false
  use ArchEthicWeb, :view

  def faucet?() do
    Application.get_env(:archethic, :faucet)
  end
end
