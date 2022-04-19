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

    # First range
    [lon_range, lat_range] = get_range(first_patch)

    lon_fdc_range = [Enum.at(lon_range, 0) * 90, Enum.at(lon_range, 1) * 90]
    lat_fdc_range = [Enum.at(lat_range, 0) * 180, Enum.at(lat_range, 1) * 180]

    lon_sign =
      Enum.at(lon_fdc_range, 0)
      |> sign()

    lat_sign =
      Enum.at(lat_fdc_range, 0)
      |> sign()

    # Second range
    [lon_range, lat_range] = get_range(second_patch)

    lon_sdc_range = [Enum.at(lon_range, 0) * 22.5, Enum.at(lon_range, 1) * 22.5]
    lat_sdc_range = [Enum.at(lat_range, 0) * 45, Enum.at(lat_range, 1) * 45]

    lon_sdc_test = [
      Enum.at(lon_sdc_range, 0) * 2 + lon_sign * 45,
      Enum.at(lon_sdc_range, 1) * 2 + lon_sign * 45
    ]

    lat_sdc_test = [
      Enum.at(lat_sdc_range, 0) * 2 + lat_sign * 90,
      Enum.at(lat_sdc_range, 1) * 2 + lat_sign * 90
    ]

    # Determine add value for third range
    lon_add =
      if Enum.at(lon_sdc_test, 0) |> is_between?(lon_fdc_range) and
           Enum.at(lon_sdc_test, 1) |> is_between?(lon_fdc_range) do
        45
      else
        0
      end

    lat_add =
      if Enum.at(lat_sdc_test, 0) |> is_between?(lat_fdc_range) and
           Enum.at(lat_sdc_test, 1) |> is_between?(lat_fdc_range) do
        90
      else
        0
      end

    # Third range
    [lon_range, lat_range] = get_range(third_patch)

    lon_tdc_range = [Enum.at(lon_range, 0) * 5.625 * 2, Enum.at(lon_range, 1) * 5.625 * 2]
    lat_tdc_range = [Enum.at(lat_range, 0) * 11.25 * 2, Enum.at(lat_range, 1) * 11.25 * 2]

    lon_tdc_test = [
      Enum.at(lon_tdc_range, 0) + lon_sign * 11.25,
      Enum.at(lon_tdc_range, 1) + lon_sign * 11.25
    ]

    lat_tdc_test = [
      Enum.at(lat_tdc_range, 0) + lat_sign * 22.5,
      Enum.at(lat_tdc_range, 1) + lat_sign * 22.5
    ]

    lon_tdc_range =
      if Enum.at(lon_tdc_test, 0) |> is_between?(lon_sdc_range) and
           Enum.at(lon_tdc_test, 1) |> is_between?(lon_sdc_range) do
        lon_tdc_test
      else
        lon_tdc_range
      end

    lat_tdc_range =
      if Enum.at(lat_tdc_test, 0) |> is_between?(lat_sdc_range) and
           Enum.at(lat_tdc_test, 1) |> is_between?(lat_sdc_range) do
        lat_tdc_test
      else
        lat_tdc_range
      end

    final_lon_range = {
      Enum.at(lon_tdc_range, 0) * 2 + lon_sign * lon_add,
      Enum.at(lon_tdc_range, 1) * 2 + lon_sign * lon_add
    }

    final_lat_range = {
      Enum.at(lat_tdc_range, 0) * 2 + lat_sign * lat_add,
      Enum.at(lat_tdc_range, 1) * 2 + lat_sign * lat_add
    }

    {final_lon_range, final_lat_range}
  end

  defp get_range(patch) when patch == "0", do: [[0.5, 1], [-1, -0.5]]
  defp get_range(patch) when patch == "1", do: [[0.5, 1], [-0.5, 0]]
  defp get_range(patch) when patch == "2", do: [[0.5, 1], [0, 0.5]]
  defp get_range(patch) when patch == "3", do: [[0.5, 1], [0.5, 1]]

  defp get_range(patch) when patch == "4", do: [[0, 0.5], [-1, -0.5]]
  defp get_range(patch) when patch == "5", do: [[0, 0.5], [-0.5, 0]]
  defp get_range(patch) when patch == "6", do: [[0, 0.5], [0, 0.5]]
  defp get_range(patch) when patch == "7", do: [[0, 0.5], [0.5, 1]]

  defp get_range(patch) when patch == "8", do: [[-0.5, 0], [-1, -0.5]]
  defp get_range(patch) when patch == "9", do: [[-0.5, 0], [-0.5, 0]]
  defp get_range(patch) when patch == "A", do: [[-0.5, 0], [0, 0.5]]
  defp get_range(patch) when patch == "B", do: [[-0.5, 0], [0.5, 1]]

  defp get_range(patch) when patch == "C", do: [[-1, -0.5], [-1, -0.5]]
  defp get_range(patch) when patch == "D", do: [[-1, -0.5], [-0.5, 0]]
  defp get_range(patch) when patch == "E", do: [[-1, -0.5], [0, 0.5]]
  defp get_range(patch) when patch == "F", do: [[-1, -0.5], [0.5, 1]]

  defp is_between?(value, range) do
    value >= Enum.at(range, 0) and value <= Enum.at(range, 1)
  end
end
