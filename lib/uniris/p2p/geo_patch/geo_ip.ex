defmodule Uniris.P2P.GeoPatch.GeoIP do
  @moduledoc false

  @behaviour Uniris.P2P.GeoPatch.GeoIPImpl

  @impl true
  @spec get_coordinates(:inet.ip_address()) :: {lat :: float(), lon :: float()}
  def get_coordinates(ip) when is_tuple(ip) do
    impl().get_coordinates(ip)
  end

  defp impl do
    :uniris
    |> Application.get_env(__MODULE__, impl: __MODULE__.IP2LocationImpl)
    |> Keyword.fetch!(:impl)
  end
end
