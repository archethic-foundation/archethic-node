defmodule ArchEthic.P2P.GeoPatch do
  @moduledoc """
  Provide functions for Geographical Patching from IP address

  Each patch is represented by 3 digits in hexadecimal form (ie. AAA, F3C)
  """

  alias __MODULE__.GeoIP

  @doc """
  Get a patch from an IP address
  """
  @spec from_ip(:inet.ip_address()) :: binary()
  def from_ip({127, 0, 0, 1}), do: compute_random_patch()

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
    # convert 90 and 180 to -90 and -180 to not get an out of bound index for array
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
    ['8', '9', 'A', 'B', 'C', 'D', 'E', 'F', '0', '1', '2', '3', '4', '5', '6', '7']
    |> Enum.at(index)
  end

  defp precision_index_patch(index1, index2) do
    [
      ['0', '1', '2', '3'],
      ['4', '5', '6', '7'],
      ['8', '9', 'A', 'B'],
      ['C', 'D', 'E', 'F']
    ]
    |> Enum.at(index1)
    |> Enum.at(index2)
  end
end
