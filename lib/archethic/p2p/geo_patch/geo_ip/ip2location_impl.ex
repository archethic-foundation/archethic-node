defmodule Archethic.P2P.GeoPatch.GeoIP.IP2LocationImpl do
  @moduledoc false

  @table_name :ip2location

  alias Archethic.P2P.GeoPatch.GeoIP

  @behaviour GeoIP

  @impl GeoIP
  def get_coordinates(ip) when is_tuple(ip) do
    unless metadata_loaded?() do
      ip_db_file = Application.app_dir(:archethic, "/priv/p2p/IP2LOCATION-LITE-DB5.BIN")
      :ip2location.new(ip_db_file, @table_name)
    end

    {:ip2locationrecord, _country_code, _country, _region, _city, _, lat, lon, _domain, _zipcode,
     _timezone, _netspeed, _iddcode, _areacode, _weather_station_code, _weather_station_name,
     _mcc, _mnc, _mobile_brand, _elevation,
     _usage_type} = :ip2location.query(:inet.ntoa(ip), @table_name)

    {lat, lon}
  end

  defp metadata_loaded? do
    case :ets.info(@table_name) do
      :undefined ->
        false

      _ ->
        true
    end
  end
end
