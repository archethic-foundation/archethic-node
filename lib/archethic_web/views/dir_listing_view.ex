defmodule ArchethicWeb.DirListingView do
  @moduledoc false
  use ArchethicWeb, :view

  @spec prepare_addresses(list(String.t())) :: String.t()
  def prepare_addresses(addresses) do
    addresses
    |> Enum.map(fn address ->
      %{
        href: %{href: Path.join(["/", "explorer", "transaction", address])},
        text: shorten_address(address)
      }
    end)
  end

  @spec shorten_address(String.t()) :: String.t()
  def shorten_address(address) do
    String.slice(address, 4..13)
  end
end
