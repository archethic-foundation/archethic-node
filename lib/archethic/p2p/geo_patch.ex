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
    list_char = Enum.concat([?0..?9, ?A..?F])
    Enum.take_random(list_char, 3) |> List.to_string()
  end

  defp compute_patch(lat, lon) do
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

    patch
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
      do_resolve_with_sign(first, first2),
      do_resolve_with_sign(second, second2)
    ]
  end

  defp do_resolve_with_sign(x1, x2) do
    if sign(x1) == sign(x2) do
      x1
    else
      x2 / 2
    end
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
