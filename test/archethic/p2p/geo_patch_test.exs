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
          {90, 180}

        # France (Bordeaux)
        {1, 1, 1, 1} ->
          {44.828114, -0.584424}

        # France (Limoges)
        {2, 2, 2, 2} ->
          {45.819792, 1.256239}

        # US (Las Vegas)
        {3, 3, 3, 3} ->
          {36.165362, -115.102552}

        # US (Phoenix)
        {4, 4, 4, 4} ->
          {33.456609, -112.033383}
      end
    end)

    assert "F1B" == GeoPatch.from_ip({88, 22, 30, 229})
    assert "C1D" == GeoPatch.from_ip({161, 235, 112, 33})
    assert "A1A" == GeoPatch.from_ip({15, 62, 246, 57})
    assert "021" == GeoPatch.from_ip({109, 164, 214, 168})
    assert "8C0" == GeoPatch.from_ip({1, 2, 3, 4})
    assert "F1F" == GeoPatch.from_ip({1, 1, 1, 1})
    assert "020" == GeoPatch.from_ip({2, 2, 2, 2})
    assert "A1B" == GeoPatch.from_ip({3, 3, 3, 3})
    assert "B14" == GeoPatch.from_ip({4, 4, 4, 4})
  end

  test "to_coordinates/1 should retrieve coordinates from geo_patch" do
    assert {{33.75, 39.375}, {-5.625, 0}} == GeoPatch.to_coordinates("F1B")
    assert {{39.375, 45}, {-84.375, -78.75}} == GeoPatch.to_coordinates("C1D")
    assert {{33.75, 39.375}, {-123.75, -118.125}} == GeoPatch.to_coordinates("A1A")
    assert {{45, 50.625}, {5.625, 11.25}} == GeoPatch.to_coordinates("021")
    assert {{-90, -84.375}, {-180, -174.375}} == GeoPatch.to_coordinates("8C0")
    assert {{39.375, 45}, {-5.625, 0}} == GeoPatch.to_coordinates("F1F")
    assert {{45, 50.625}, {0, 5.625}} == GeoPatch.to_coordinates("020")
    assert {{33.75, 39.375}, {-118.125, -112.5}} == GeoPatch.to_coordinates("A1B")
    assert {{28.125, 33.75}, {-112.5, -106.875}} == GeoPatch.to_coordinates("B14")
  end
end
