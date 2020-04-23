defmodule UnirisCore.P2P.GeoPatch do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, [], {:continue, :load_geoip_lookup}}
  end

  def handle_continue(:load_geoip_lookup, state) do
    :ip2location.new(Application.app_dir(:uniris_core, "/priv/p2p/IP2LOCATION-LITE-DB5.BIN"))
    {:noreply, state}
  end

  def handle_call({:get_patch_from_ip, {127, 0, 0, 1}}, _, state) do
    # Use random when it is on local network
    list_char = Enum.concat([?0..?9, ?A..?F])
    geo_patch = Enum.take_random(list_char, 3) |> List.to_string()
    {:reply, geo_patch, state}
  end

  def handle_call({:get_patch_from_ip, ip}, _, state) do
    ip_string = ip |> Tuple.to_list() |> Enum.join(".") |> String.to_charlist()

    {:ip2locationrecord, _country_code, _country, _region, _city, _, lat, lon, _, _, _, _, _, _,
     _, _, _, _, _, 0.0, _} = :ip2location.query(ip_string)

    lat_sign = sign(lat)
    lon_sign = sign(lon)

    fdc = [lat / 90, lon / 180]

    sd =
      [(lat - lat_sign * 45) / 2, (lon - lon_sign * 90) / 2]
      |> resolve_with_sign([lat, lon])

    sdc = [List.first(sd) / 22.5, List.last(sd) / 45]

    td =
      [
        (List.first(sd) - lat_sign * 11.25) / 2,
        (List.last(sd) - lon_sign * 22.5) / 2
      ]
      |> resolve_with_sign(sd)

    tdc = [List.first(td) / 5.625, List.last(td) / 11.25]

    patch =
      [index_patch(fdc), index_patch(sdc), index_patch(tdc)]
      |> Enum.join("")

    {:reply, patch, state}
  end

  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < -0.5 and s_i >= -1, do: '0'
  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < 0 and s_i >= -0.5, do: '1'
  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < 0.5 and s_i >= 0, do: '2'
  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < 1 and s_i >= 0.5, do: '3'

  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < -0.5 and s_i >= -1, do: '4'
  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < 0 and s_i >= -0.5, do: '5'
  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < 0.5 and s_i >= 0, do: '6'
  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < 1 and s_i >= 0.5, do: '7'

  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < -0.5 and s_i >= -1, do: '8'
  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < 0 and s_i >= -0.5, do: '9'
  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < 0.5 and s_i >= 0, do: 'A'
  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < 1 and s_i >= 0.5, do: 'B'

  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < -0.5 and s_i >= -1, do: 'C'
  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < 0 and s_i >= -0.5, do: 'D'
  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < 0.5 and s_i >= 0, do: 'E'
  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < 1 and s_i >= 0.5, do: 'F'

  defp sign(number) when number < 0, do: -1
  defp sign(number) when number >= 0, do: 1

  defp resolve_with_sign([first, second], [first2, second2]) do
    [
      if sign(first) == sign(first2) do
        first
      else
        first2 / 2
      end,
      if sign(second) == sign(second2) do
        second
      else
        second2 / 2
      end
    ]
  end

  @spec from_ip(:inet.ip_address()) :: binary()
  def from_ip({_, _, _, _} = ip) do
    GenServer.call(__MODULE__, {:get_patch_from_ip, ip})
  end
end
