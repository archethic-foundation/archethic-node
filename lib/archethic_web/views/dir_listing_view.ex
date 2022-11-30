defmodule ArchethicWeb.DirListingView do
  @moduledoc false
  use ArchethicWeb, :view

  @spec prepare_addresses(list(String.t())) :: list(map())
  def prepare_addresses(addresses) do
    explorer_url =
      Keyword.fetch!(
        Application.get_env(:archethic, ArchethicWeb.Endpoint),
        :explorer_url
      )

    addresses
    |> Enum.map(fn address ->
      %{
        href: %{
          href: Path.join([explorer_url, "transaction", address])
        },
        text: shorten_address(address)
      }
    end)
  end

  @spec shorten_address(String.t()) :: String.t()
  def shorten_address(address) do
    String.slice(address, 4..7)
  end
end
