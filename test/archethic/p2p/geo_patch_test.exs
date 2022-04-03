defmodule ArchEthic.P2P.GeoPatchTest do
  @moduledoc """
  This module defines the test case to be used by
  geopatch tests.
  """

  use ExUnit.Case

  alias ArchEthic.P2P.GeoPatch

  import Mox

  test "from_ip/1 should compute patch from coordinates" do
    stub(MockGeoIP, :get_coordinates, fn ip ->
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

        # Edge value
        {1, 2, 3, 4} ->
          {-45.0, 0.0}
      end
    end)

    assert "F1B" == GeoPatch.from_ip({88, 22, 30, 229})
    assert "C1D" == GeoPatch.from_ip({161, 235, 112, 33})
    assert "A1A" == GeoPatch.from_ip({15, 62, 246, 57})
    assert "021" == GeoPatch.from_ip({109, 164, 214, 168})
    assert "0E0" == GeoPatch.from_ip({1, 2, 3, 4})
  end
end
