defmodule Archethic.P2P.GeoPatch.GeoIP.IP2LocationTest do
  use ExUnit.Case

  alias Archethic.P2P.GeoPatch.GeoIP.IP2LocationImpl, as: GeoIP

  test "get_coordinates/1 should retrieve coordinates from ip" do
    {lat, lon} = GeoIP.get_coordinates({93, 22, 131, 35})
    assert 48.29 == Float.round(lat, 2)
    assert 6.95 == Float.round(lon, 2)
  end
end
