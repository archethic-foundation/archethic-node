defmodule Archethic.P2P.GeoPatch.GeoIP.IP2LocationImpl do
  @moduledoc false

  alias Archethic.P2P.GeoPatch.GeoIP
  alias Geolix

  @behaviour GeoIP

  @impl GeoIP
  def get_coordinates(ip) when is_tuple(ip) do
    %{location: %{latitude: lat, longitude: lon}} = Geolix.lookup(ip, where: :city)

    {lat, lon}
  end
end
