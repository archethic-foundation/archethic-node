defmodule Uniris.P2P.GeoPatch.GeoIP.IP2LocationImpl do
  @moduledoc false

  @ip_db_file Application.app_dir(:uniris, "/priv/p2p/IP2LOCATION-LITE-DB5.BIN")
  @table_name :ip2location

  @behaviour Uniris.P2P.GeoPatch.GeoIPImpl

  @impl true
  def get_coordinates(ip) when is_tuple(ip) do
    unless metadata_loaded?() do
      :ip2location.new(@ip_db_file, @table_name)
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
