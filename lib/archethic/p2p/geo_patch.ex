defmodule Archethic.P2P.GeoPatch do
  @moduledoc """
  Provide functions for Geographical Patching from IP address

  Each patch is represented by 3 digits in hexadecimal form (ie. AAA, F3C)
  """

  alias __MODULE__.GeoIP

  @doc """
  Get a patch from an IP address
  Null island, patch for local host.
  """
  @spec from_ip(:inet.ip_address()) :: binary()
  def from_ip({127, 0, 0, 1}), do: "000"

  def from_ip(ip) when is_tuple(ip) do
    case GeoIP.get_coordinates(ip) do
      {0.0, 0.0} ->
        compute_random_patch()

      {lat, lon} ->
        compute_patch(lat, lon)
    end
  end

  defp compute_random_patch do
    list_char1 = Enum.concat([?0..?9, ?A..?F])
    list_char2 = Enum.concat([?0..?3, ?C..?F])

    Enum.take_random(list_char1, 2)
    |> List.insert_at(1, Enum.take_random(list_char2, 1))
    |> List.to_string()
  end

  defp compute_patch(lat, lon) do
    # convert 90 and 180 to -90 and -180 to not get an out of bound index
    lat = if(lat == 90, do: -90) || lat
    lon = if(lon == 180, do: -180) || lon

    lon_pos = (lon + 180) / 22.5
    # Adding 4 to have second digit hex value from C to 3
    lat_pos = (lat + 90) / 22.5 + 4

    first_digit = main_index_patch(trunc(lon_pos))
    second_digit = main_index_patch(trunc(lat_pos))

    lat_precision = ((lat_pos - trunc(lat_pos)) / 0.25) |> trunc()
    lon_precision = ((lon_pos - trunc(lon_pos)) / 0.25) |> trunc()

    third_digit = precision_index_patch(lat_precision, lon_precision)

    [first_digit, second_digit, third_digit]
    |> Enum.join("")
  end

  defp main_index_patch(index) do
    {'8', '9', 'A', 'B', 'C', 'D', 'E', 'F', '0', '1', '2', '3', '4', '5', '6', '7'}
    |> elem(index)
  end

  defp precision_index_patch(index1, index2) do
    {
      {'0', '1', '2', '3'},
      {'4', '5', '6', '7'},
      {'8', '9', 'A', 'B'},
      {'C', 'D', 'E', 'F'}
    }
    |> elem(index1)
    |> elem(index2)
  end

  @doc """
  Get range of longitude / latitude coordinates from geo patch
  """
  @spec to_coordinates(binary()) :: {{float(), float()}, {float(), float()}}
  def to_coordinates(geo_patch) do
    [first_patch, second_patch, third_patch] = String.codepoints(geo_patch)

    lon_init = get_main_index(first_patch) * 22.5
    lat_init = (get_main_index(second_patch) - 4) * 22.5

    {lon_precision, lat_precision} =
      with {index, _} <- Integer.parse(third_patch, 16) do
        {rem(index, 4), trunc(index / 4)}
      end

    final_lon_range = {
      lon_init + lon_precision * 5.625 - 180,
      lon_init + (lon_precision + 1) * 5.625 - 180
    }

    final_lat_range = {
      lat_init + lat_precision * 5.625 - 90,
      lat_init + (lat_precision + 1) * 5.625 - 90
    }

    {final_lat_range, final_lon_range}
  end

  defp get_main_index(value) do
    ["8", "9", "A", "B", "C", "D", "E", "F", "0", "1", "2", "3", "4", "5", "6", "7"]
    |> Enum.find_index(fn el -> el == value end)
  end
end
