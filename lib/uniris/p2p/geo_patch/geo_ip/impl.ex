defmodule Uniris.P2P.GeoPatch.GeoIPImpl do
  @moduledoc false

  @callback get_coordinates(:inet.ip_address()) :: {latitude :: float(), longitude :: float()}
end
