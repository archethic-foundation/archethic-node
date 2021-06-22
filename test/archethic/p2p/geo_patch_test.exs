defmodule ArchEthic.P2P.GeoPatchTest do
  use ExUnit.Case

  alias ArchEthic.P2P.GeoPatch

  import Mox

  test "from_ip/1 should compute patch from coordinates" do
    expect(MockGeoIP, :get_coordinates, fn ip ->
      case ip do
        # Spain (Alicante)
        {88, 22, 30, 229} ->
          {38.345170, -0.481490}

        # US (Columbus)
        {161, 235, 112, 33} ->
          {39.964263, -83.003268}

        # US (San José)
        {15, 62, 246, 57} ->
          {37.409911, -122.16040}

        # Switzerland (Zurich)
        {109, 164, 214, 168} ->
          {47.366670, 8.550000}
      end
    end)

    assert "511" == GeoPatch.from_ip({88, 22, 30, 229})
    assert "500" == GeoPatch.from_ip({161, 235, 112, 33})
    assert "410" == GeoPatch.from_ip({15, 62, 246, 57})
    assert "266" == GeoPatch.from_ip({109, 164, 214, 168})
  end
end
